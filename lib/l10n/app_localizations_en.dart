// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'OpenHand';

  @override
  String get appTagline => 'An open, stable, and extensible desktop workspace';

  @override
  String get newThread => 'New Thread';

  @override
  String get skills => 'Skills';

  @override
  String get memory => 'Memory';

  @override
  String get mcp => 'MCP';

  @override
  String get settings => 'Settings';

  @override
  String get threads => 'Threads';

  @override
  String get threadsLoadMore => 'Load More Threads';

  @override
  String get composerHint =>
      'Ask OpenHand anything, use / for actions, and @ for context';

  @override
  String get composerSend => 'Send';

  @override
  String get chatSending => 'Sending';

  @override
  String get chatRequestFailed =>
      'Model request failed. Check the model configuration, network connectivity, or protocol type.';

  @override
  String get placeholderComingSoon =>
      'Additional modules will be added here step by step.';

  @override
  String get settingsTitle => 'Settings Center';

  @override
  String get settingsSubtitle =>
      'Manage general preferences, AI models, MCP services, skill storage, memory, and app information here.';

  @override
  String get settingsFilePathLabel => 'Settings File';

  @override
  String get themeSectionTitle => 'App Theme';

  @override
  String get themeSectionBody =>
      'Choose the brightness style that fits your current workspace.';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themePaletteSectionTitle => 'Theme Palette';

  @override
  String get themePaletteSectionBody =>
      'Choose a global color preset. OpenHand will derive the Material 3 Expressive surfaces and accents from it.';

  @override
  String get themePresetDarkNightPurple => 'Dark Night Purple';

  @override
  String get themePresetDeepSeaBlue => 'Deep Sea Blue';

  @override
  String get themePresetMistGray => 'Mist Gray';

  @override
  String get themePresetObsidianBlack => 'Obsidian Black';

  @override
  String get themePresetPolarWhite => 'Polar White';

  @override
  String get themePresetFrostMorningBlue => 'Frost Morning Blue';

  @override
  String get themePresetDuskMountainGreen => 'Dusk Mountain Green';

  @override
  String get themePresetNebulaPurple => 'Nebula Purple';

  @override
  String get themePresetEmberOrange => 'Ember Orange';

  @override
  String get themePresetTundraGreen => 'Tundra Green';

  @override
  String get themePresetMoonShadowSilver => 'Moon Shadow Silver';

  @override
  String get themePresetAmberGold => 'Amber Gold';

  @override
  String get themePresetRainyCyan => 'Rainy Cyan';

  @override
  String get themePresetGraphiteGray => 'Graphite Gray';

  @override
  String get themePresetGlacierBlue => 'Glacier Blue';

  @override
  String get themePresetBlazeRed => 'Blaze Red';

  @override
  String get themePresetNightfallBlue => 'Nightfall Blue';

  @override
  String get themePresetColdMoonWhite => 'Cold Moon White';

  @override
  String get themePresetPineInk => 'Pine Ink';

  @override
  String get themePresetSkyCyan => 'Sky Cyan';

  @override
  String get languageSectionTitle => 'App Language';

  @override
  String get languageSectionBody =>
      'Change the interface language and apply it immediately.';

  @override
  String get languageSimplifiedChinese => 'Simplified Chinese';

  @override
  String get languageTraditionalChinese => 'Traditional Chinese';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'French';

  @override
  String get languageGerman => 'German';

  @override
  String get languageJapanese => 'Japanese';

  @override
  String get aboutSectionTitle => 'About';

  @override
  String get aboutSectionBody =>
      'OpenHand is currently in its foundation stage, focused on a stable desktop structure, visual baseline, and extensible architecture.';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutPackage => 'Package';

  @override
  String get aboutPlatforms => 'Platforms';

  @override
  String get aboutPlatformsValue => 'macOS 15+ / Windows 10+';

  @override
  String get aboutBuild => 'Build';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get exportProgressCancelling => 'Cancelling…';

  @override
  String get readerFileTypeText => 'Plain text';

  @override
  String get readerFileTypeCode => 'Code';

  @override
  String knowledgeReaderNoModelForType(Object type) {
    return 'No reader model can read $type.';
  }

  @override
  String get permissionLabel => 'Full Access';

  @override
  String get settingsCategoryGeneral => 'General';

  @override
  String get settingsCategoryAi => 'AI';

  @override
  String get settingsCategorySkills => 'Skills';

  @override
  String get settingsCategoryMemory => 'Memory';

  @override
  String get mcpSectionTitle => 'MCP Services';

  @override
  String get mcpSectionBody =>
      'Manage the global MCP switch and the service configuration file path. Creating, updating, deleting, and enabling services all sync to the MCP JSON file.';

  @override
  String get mcpEnabledLabel => 'Enable MCP Services';

  @override
  String get mcpEnabledBody =>
      'When disabled, MCP capabilities stay off at runtime while keeping the saved server configurations.';

  @override
  String get mcpFilePathLabel => 'MCP Config File';

  @override
  String get mcpOpenDirectory => 'Open Directory';

  @override
  String get mcpStdioCacheResetAction => 'Reset stdio package cache';

  @override
  String get mcpStdioCacheResetConfirmTitle =>
      'Reset stdio isolated package cache?';

  @override
  String get mcpStdioCacheResetConfirmBody =>
      'This will delete the npm/uv/pip caches under ~/.openhand/mcp/package-cache. The next stdio MCP launch will re-download dependencies. Your global ~/.npm is not affected.';

  @override
  String get mcpStdioCacheResetConfirm => 'Reset';

  @override
  String get mcpStdioCacheResetCancel => 'Cancel';

  @override
  String get mcpStdioCacheResetDone => 'Isolated cache cleared.';

  @override
  String get mcpStdioCacheResetFailed =>
      'Reset failed. Please remove ~/.openhand/mcp/package-cache manually.';

  @override
  String get pluginServiceTitle => 'Plugins';

  @override
  String get pluginServiceSubtitle =>
      'Manage optional plugin installation, updates, and removal. Plugins add runtime capabilities to OpenHand.';

  @override
  String get pluginServiceRescan => 'Rescan';

  @override
  String get pluginServiceScanning => 'Scanning local plugin environment…';

  @override
  String get pluginServiceScanFailed => 'Plugin scan failed';

  @override
  String get pluginServiceActionInstall => 'Install';

  @override
  String get pluginServiceActionUpdate => 'Update';

  @override
  String get pluginServiceActionUninstall => 'Uninstall';

  @override
  String get pluginServiceActionEnable => 'Enable';

  @override
  String get pluginServiceActionDisable => 'Disable';

  @override
  String get pluginServiceStatusInstalled => 'Installed';

  @override
  String get pluginServiceStatusNotInstalled => 'Not Installed';

  @override
  String get pluginServiceStatusInstalling => 'Installing…';

  @override
  String get pluginServiceStatusUpdating => 'Updating…';

  @override
  String get pluginServiceStatusUninstalling => 'Uninstalling…';

  @override
  String get pluginServiceStatusError => 'Error';

  @override
  String get pluginServiceCheckUpdates => 'Check Updates';

  @override
  String get pluginServiceMcpService => 'MCP Service';

  @override
  String pluginServiceInstallDependencyRequired(Object dependency) {
    return '$dependency must be installed first';
  }

  @override
  String pluginServiceInstallConfirmTitle(Object plugin) {
    return 'Install $plugin?';
  }

  @override
  String pluginServiceInstallConfirmMessage(Object plugin) {
    return 'This will install $plugin. Dependencies may be downloaded.';
  }

  @override
  String pluginServiceInstallSuccess(Object plugin) {
    return '$plugin installed';
  }

  @override
  String pluginServiceInstallFailure(Object plugin) {
    return '$plugin install failed';
  }

  @override
  String pluginServiceUpdateConfirmTitle(Object plugin) {
    return 'Update $plugin?';
  }

  @override
  String pluginServiceUpdateConfirmMessage(
    Object plugin,
    Object currentVersion,
    Object latestVersion,
  ) {
    return 'Update $plugin from $currentVersion to $latestVersion.';
  }

  @override
  String pluginServiceUpdateSuccess(Object plugin) {
    return '$plugin updated';
  }

  @override
  String pluginServiceUpdateFailure(Object plugin) {
    return '$plugin update failed';
  }

  @override
  String get pluginServiceCheckUpdateFailed => 'Failed to check updates';

  @override
  String pluginServiceNewVersionAvailable(Object version) {
    return 'New version available: $version';
  }

  @override
  String get pluginServiceNoUpdatesAvailable => 'No updates available';

  @override
  String pluginServiceUninstallBlocked(Object dependent, Object plugin) {
    return '$dependent depends on $plugin. Uninstall it first.';
  }

  @override
  String pluginServiceUninstallConfirmTitle(Object plugin) {
    return 'Uninstall $plugin?';
  }

  @override
  String pluginServiceUninstallConfirmMessage(Object plugin) {
    return 'This will remove $plugin. This cannot be undone.';
  }

  @override
  String pluginServiceUninstallSuccess(Object plugin) {
    return '$plugin uninstalled';
  }

  @override
  String pluginServiceUninstallFailure(Object plugin) {
    return '$plugin uninstall failed';
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
  String get pluginServiceRuntimeArch => 'Arch';

  @override
  String pluginServiceLogLineCount(Object count) {
    return 'Logs: $count lines';
  }

  @override
  String get pluginServiceWaitingForOutput => 'Waiting for output…';

  @override
  String get pluginServiceExecuting => 'Executing…';

  @override
  String get pluginServiceCompleted => 'Completed';

  @override
  String get pluginServiceVersion => 'Version';

  @override
  String get pluginServiceUpdateAvailable => 'Update available';

  @override
  String get pluginServiceDependsOn => 'Depends on';

  @override
  String get pluginServiceRequiredBy => 'Required by';

  @override
  String get pluginServiceNone => 'None';

  @override
  String pluginServiceDetailTitle(Object plugin) {
    return '$plugin Details';
  }

  @override
  String get pluginServiceDetailBasicInfo => 'Basic Info';

  @override
  String get pluginServiceDetailName => 'Name';

  @override
  String get pluginServiceDetailDescription => 'Description';

  @override
  String get pluginServiceDetailStatus => 'Status';

  @override
  String get pluginServiceDetailEnvironment => 'Environment';

  @override
  String get pluginServiceDetailFileSystem => 'File System';

  @override
  String get pluginServiceDetailDependencies => 'Dependencies';

  @override
  String get pluginServiceThreadTemplates => 'Thread templates';

  @override
  String get pluginServiceTemplates => 'Templates';

  @override
  String get pluginServiceMcpPackage => 'MCP Package';

  @override
  String get pluginServiceMcpBrowserDescription =>
      'MCP server for browser automation';

  @override
  String get pluginServiceDetailProcessors => 'Processors';

  @override
  String get pluginServiceDetailInstallPath => 'Install Path';

  @override
  String get pluginServiceDetailInstallationTarget => 'Install Target';

  @override
  String get pluginServiceDetailInstallMethod => 'Install Method';

  @override
  String get pluginServiceDetailTargetOs => 'Target OS';

  @override
  String get pluginServiceDetailSupportedPlatforms => 'Supported Platforms';

  @override
  String get pluginServiceDetailPackageName => 'Package Name';

  @override
  String get pluginServiceDetailBinaryName => 'Command Name';

  @override
  String get pluginServiceDetailRepository => 'Repository';

  @override
  String get pluginServiceDetailDocumentation => 'Official Documentation';

  @override
  String get pluginServiceDetailInstallCommand => 'Install Command';

  @override
  String get pluginServiceDetailUpgradeCommand => 'Upgrade Command';

  @override
  String get pluginServiceDetailUninstallCommand => 'Uninstall Command';

  @override
  String get pluginServiceDetailExecutablePath => 'Executable Entry';

  @override
  String get pluginServiceDetailCacheDirectory => 'Cache Directory';

  @override
  String get pluginServiceDetailNpmGlobalRoot => 'npm Global Root';

  @override
  String get pluginServiceDetailCurrentVersion => 'Version';

  @override
  String get pluginServiceDetailLatestVersion => 'Latest';

  @override
  String get pluginServiceDetailBoundPython => 'Bound Python';

  @override
  String get pluginServiceDetailDesktopAppDetected => 'Desktop app detected';

  @override
  String get pluginServiceDetailDaemonRunning => 'Daemon running';

  @override
  String get pluginServiceDetailCliAvailable => 'CLI available';

  @override
  String get pluginServiceDetailDockerContext => 'Docker context';

  @override
  String get pluginServiceDetailServerVersion => 'Server version';

  @override
  String get pluginServiceDetailDockerOs => 'Docker OS';

  @override
  String get pluginServiceDetailDockerRootDir => 'Docker root dir';

  @override
  String get pluginServiceDetailDaemonName => 'Daemon name';

  @override
  String get pluginServiceDetailOsType => 'OS type';

  @override
  String get pluginServiceDetailArchitecture => 'Architecture';

  @override
  String get pluginServiceDetailComposeVersion => 'Compose version';

  @override
  String get pluginServiceDetailDockerDaemonRunning => 'Docker daemon running';

  @override
  String get pluginServiceDetailOpenHandManaged => 'OpenHand managed';

  @override
  String get pluginServiceDetailContainerId => 'Container ID';

  @override
  String get pluginServiceDetailContainerName => 'Container name';

  @override
  String get pluginServiceDetailContainerStatus => 'Container status';

  @override
  String get pluginServiceDetailRunning => 'Running';

  @override
  String get pluginServiceDetailStartedAt => 'Started at';

  @override
  String get pluginServiceDetailFinishedAt => 'Finished at';

  @override
  String get pluginServiceDetailRestartCount => 'Restart count';

  @override
  String get pluginServiceDetailExitCode => 'Exit code';

  @override
  String get pluginServiceDetailImage => 'Image';

  @override
  String get pluginServiceDetailImageId => 'Image ID';

  @override
  String get pluginServiceDetailPorts => 'Ports';

  @override
  String get pluginServiceDetailRestartPolicy => 'Restart policy';

  @override
  String get pluginServiceDetailRestEndpoint => 'REST endpoint';

  @override
  String get pluginServiceDetailGrpcEndpoint => 'gRPC endpoint';

  @override
  String get pluginServiceDetailDataDirectory => 'Data directory';

  @override
  String get pluginServiceDetailHealthResponse => 'Health response';

  @override
  String get pluginServiceDetailHealthTitle => 'Health title';

  @override
  String get pluginServiceDetailCollectionCount => 'Collection count';

  @override
  String get pluginServiceDetailRuntimeCapabilities => 'Runtime capabilities';

  @override
  String get pluginServiceDetailApplicationPath => 'Application path';

  @override
  String get pluginServiceDetailReleaseChannel => 'Release channel';

  @override
  String get pluginServiceDetailVersionSource => 'Version source';

  @override
  String get pluginServiceDetailVersionApi => 'Version API';

  @override
  String get pluginServiceDetailBrowserKind => 'Browser type';

  @override
  String get pluginServiceDetailCdpTransport => 'CDP transport';

  @override
  String get pluginServiceDetailCdpEndpoint => 'CDP endpoint';

  @override
  String get pluginServiceDetailProfileStrategy => 'Profile strategy';

  @override
  String get pluginServiceDetailCaptureScope => 'Capture scope';

  @override
  String get pluginServiceDetailCredentialPolicy => 'Credential protection';

  @override
  String get pluginServiceDetailSessionCleanup => 'Session cleanup';

  @override
  String get pluginServiceDetailUpdatePolicy => 'Update policy';

  @override
  String get pluginServiceDetailUninstallPolicy => 'Uninstall policy';

  @override
  String get pluginServiceDetailOfficialSite => 'Official site';

  @override
  String pluginServiceMcpInstalledVersion(Object version) {
    return 'Installed v$version';
  }

  @override
  String get pluginServiceMcpOperationTimeout =>
      '[timeout] Operation timed out; process terminated';

  @override
  String pluginServiceMcpOperationCompleted(Object action, Object exitCode) {
    return '✓ $action completed (exit code: $exitCode)';
  }

  @override
  String pluginServiceMcpOperationFailed(Object action, Object exitCode) {
    return '✗ $action failed (exit code: $exitCode)';
  }

  @override
  String pluginServiceMcpOperationError(Object error) {
    return '✗ Error: $error';
  }

  @override
  String get pluginServiceMcpVerificationFailed =>
      'MCP state verification failed after the operation';

  @override
  String get pluginServiceDescriptionNodejs =>
      'JavaScript runtime for JS/TS scripts and toolchains';

  @override
  String get pluginServiceDescriptionPlaywright =>
      'Browser automation test framework for Chromium, Firefox, and WebKit';

  @override
  String get pluginServiceDescriptionHermesAgent =>
      'Hermes Agent runtime for agent orchestration, self-learning, and skill refinement';

  @override
  String get pluginServiceDescriptionPython =>
      'Python runtime for scripts, libraries, and extensions';

  @override
  String get pluginServiceDescriptionPip =>
      'Python package manager for installing, upgrading, and managing libraries';

  @override
  String get pluginServiceDescriptionJava =>
      'JDK runtime for Android static analysis tools such as apktool and jadx';

  @override
  String get pluginServiceDescriptionFrida =>
      'Dynamic instrumentation and Hook toolchain for Android runtime validation';

  @override
  String get pluginServiceDescriptionMitmproxy =>
      'HTTP(S) proxy capture tool for Web and Android traffic forensics';

  @override
  String get pluginServiceDescriptionApktool =>
      'APK unpacking and smali analysis tool';

  @override
  String get pluginServiceDescriptionJadx => 'DEX / APK Java decompiler';

  @override
  String get pluginServiceDescriptionRadare2 =>
      'Binary static analysis and ELF / native so reverse-engineering tool';

  @override
  String get pluginServiceDescriptionBlutter =>
      'Flutter Dart AOT recovery tool for libapp.so analysis';

  @override
  String get pluginServiceDescriptionDoldrums =>
      'Flutter snapshot / ELF auxiliary analysis tool';

  @override
  String get pluginServiceDescriptionAnythingAnalyzer =>
      'Protocol analysis and MCP Server tool for capture, analysis, and Agent integration';

  @override
  String get pluginServiceDescriptionDocker =>
      'Container runtime for the local Qdrant vector database service';

  @override
  String get pluginServiceDescriptionQdrant =>
      'Local vector database for knowledge-base embedding indexes and retrieval';

  @override
  String get pluginServiceDescriptionPostgresql =>
      'Relational database service for AI exposure scan jobs and audit data';

  @override
  String get pluginServiceDescriptionRedis =>
      'In-memory data service for AI exposure scan caching and task queues';

  @override
  String get pluginServiceDescriptionDingtalkWorkspaceCli =>
      'DingTalk Workspace CLI for AI Agent workflows in DingTalk';

  @override
  String get pluginServiceDescriptionGoogleChrome =>
      'Local Chrome runtime for native CDP page and network capture in forum hunts';

  @override
  String get pluginServiceDetailExternalService => 'External service';

  @override
  String get pluginServiceDetailServiceRunning => 'Service running';

  @override
  String get pluginServiceDetailEndpoint => 'Service endpoint';

  @override
  String get pluginServiceTemplateWebReverseExpert => 'Web Reverse Expert';

  @override
  String get pluginServiceTemplateAndroidReverseExpert =>
      'Android Reverse Expert';

  @override
  String get pluginServiceTemplateHermesTalker => 'Hermes Talker';

  @override
  String get mcpStdioMirrorModeLabel => 'Mirror registry mode';

  @override
  String get mcpStdioMirrorModeBody =>
      'On stdio MCP cold start, whether to inject China mirrors (npmmirror / Tsinghua PyPI). auto = follow system locale; force on / off = ignore locale. The OPENHAND_MCP_MIRROR=on/off env var still wins at runtime.';

  @override
  String get mcpStdioMirrorModeAuto => 'Follow locale';

  @override
  String get mcpStdioMirrorModeForceOn => 'Force on';

  @override
  String get mcpStdioMirrorModeForceOff => 'Force off';

  @override
  String get mcpStdioMirrorModeStatusInjected =>
      'Active: injecting npmmirror / Tsinghua PyPI';

  @override
  String get mcpStdioMirrorModeStatusBypassed =>
      'Active: official registry, no mirror injection';

  @override
  String mcpStdioMirrorModeStatusReason(Object reason) {
    return 'Source: $reason';
  }

  @override
  String get mcpStdioMirrorModeReasonEnv => 'OPENHAND_MCP_MIRROR env var';

  @override
  String get mcpStdioMirrorModeReasonSetting => 'Settings override';

  @override
  String mcpStdioMirrorModeReasonLocale(Object locale) {
    return 'System locale ($locale)';
  }

  @override
  String get mcpStdioMirrorModeReconnectAction =>
      'Reconnect enabled servers with new setting';

  @override
  String get mcpStdioMirrorModeReconnectDone =>
      'Reconnect triggered. Next call will respawn the process with the new mirror.';

  @override
  String mcpStdioDialogLogsTitle(Object name) {
    return '$name Logs';
  }

  @override
  String mcpStdioDialogRuntimeDetailsTitle(Object name) {
    return '$name Runtime Details';
  }

  @override
  String mcpStdioDialogRunningPid(Object pid) {
    return 'Running · PID $pid';
  }

  @override
  String get mcpStdioDialogStopped => 'Stopped';

  @override
  String get mcpStdioDialogAutoScroll => 'Auto-scroll';

  @override
  String get mcpStdioDialogCopyLogs => 'Copy logs';

  @override
  String get mcpStdioDialogClearLogs => 'Clear logs';

  @override
  String get mcpStdioDialogCopiedToClipboard => 'Copied to clipboard';

  @override
  String get mcpStdioDialogNoLogOutput => 'No log output yet';

  @override
  String mcpStdioDialogLineCount(int count) {
    return '$count lines';
  }

  @override
  String mcpStdioDialogUptime(Object uptime) {
    return 'Up $uptime';
  }

  @override
  String get mcpStdioDialogRefresh => 'Refresh';

  @override
  String get settingsScraplingRuntimeActionInstall => 'Install';

  @override
  String get settingsScraplingRuntimeActionUninstall => 'Uninstall';

  @override
  String settingsScraplingRuntimeCommand(Object action) {
    return '$action Scrapling runtime';
  }

  @override
  String get settingsScraplingRuntimeInstallTitle =>
      'Install Scrapling Runtime';

  @override
  String get settingsScraplingRuntimeUninstallTitle =>
      'Uninstall Scrapling Runtime';

  @override
  String get settingsScraplingRuntimeInstalling => 'Installing…';

  @override
  String get settingsScraplingRuntimeUninstalling => 'Uninstalling…';

  @override
  String get settingsScraplingRuntimeInstalled => 'Installed';

  @override
  String get settingsScraplingRuntimeUninstalled => 'Uninstalled';

  @override
  String get settingsScraplingRuntimeFailed => 'Failed';

  @override
  String get settingsScraplingRuntimeCertificateDiagnosis =>
      'Diagnosis: Python / pip in the current environment cannot validate the PyPI certificate chain. Check system CA certificates, proxy interception certificates, or configure a valid certificate file for Python.';

  @override
  String get settingsScraplingRuntimeCopiedAllLogs => 'Copied all logs';

  @override
  String get settingsScraplingRuntimeCopyLogs => 'Copy Logs';

  @override
  String get mcpStdioDialogProcessStatus => 'Process Status';

  @override
  String get mcpStdioDialogServiceConfig => 'Service Config';

  @override
  String get mcpStdioDialogType => 'Type';

  @override
  String get mcpStdioDialogCommand => 'Command';

  @override
  String get mcpStdioDialogArgs => 'Args';

  @override
  String get mcpStdioDialogEnabled => 'Enabled';

  @override
  String get mcpStdioDialogYes => 'Yes';

  @override
  String get mcpStdioDialogNo => 'No';

  @override
  String get mcpStdioDialogEnvironment => 'Environment';

  @override
  String get mcpStdioDialogError => 'Error';

  @override
  String get mcpStdioDialogDepsTitle => 'Dependency Management';

  @override
  String get mcpStdioDialogNoDepsToManage =>
      'This service is not package-manager-based (npx / uvx). No deps to manage.';

  @override
  String mcpStdioDialogInstalledVersion(Object version) {
    return 'Installed v$version';
  }

  @override
  String get mcpStdioDialogUnknownVersion => '?';

  @override
  String get mcpStdioDialogNotGloballyInstalled => 'Not globally installed';

  @override
  String get mcpStdioDialogInstall => 'Install';

  @override
  String get mcpStdioDialogUpdate => 'Update';

  @override
  String get mcpStdioDialogUninstall => 'Uninstall';

  @override
  String mcpStdioDialogLatestVersion(Object version) {
    return 'Latest: $version';
  }

  @override
  String get mcpStdioDialogUpdateAvailableSuffix => ' (update available)';

  @override
  String get mcpStdioDialogOperationTimeout =>
      '[timeout] Operation timed out; process terminated';

  @override
  String mcpStdioDialogOperationCompleted(
    Object time,
    Object action,
    int exitCode,
  ) {
    return '[$time] ✓ $action completed (exit code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationFailed(
    Object time,
    Object action,
    int exitCode,
  ) {
    return '[$time] ✗ $action failed (exit code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationFailedPlain(Object action, int exitCode) {
    return '$action failed (exit code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationException(Object time, Object error) {
    return '[$time] ✗ Exception: $error';
  }

  @override
  String mcpStdioDialogWarmCache(Object time) {
    return '[$time] Warming isolated cache…';
  }

  @override
  String mcpStdioDialogWarmCacheDone(Object time) {
    return '[$time] ✓ Cache warmed';
  }

  @override
  String mcpStdioDialogWarmCacheSkipped(Object time, Object error) {
    return '[$time] Cache warm skipped: $error';
  }

  @override
  String get mcpAutoProbeConcurrencyLabel => 'MCP check/fetch concurrency';

  @override
  String get mcpAutoProbeConcurrencyBody =>
      'Maximum number of MCP services checked or fetched in parallel. Default 5; lowering reduces resource pressure, raising speeds up many servers.';

  @override
  String get mcpAutoProbeConcurrencySave => 'Save concurrency';

  @override
  String get mcpAutoProbeConcurrencySaved =>
      'MCP check/fetch concurrency saved.';

  @override
  String get mcpAutoProbeConcurrencyInvalid =>
      'Please enter an integer between 1 and 32.';

  @override
  String get mcpProbeDetailsTitle => 'MCP Probe Details';

  @override
  String get mcpProbePoolActive => 'Probe pool active';

  @override
  String get mcpProbePoolIdle => 'Probe pool idle';

  @override
  String get mcpProbePoolStatusTitle => 'Pool Status';

  @override
  String mcpProbeSlots(int active, int total) {
    return 'Slots $active/$total';
  }

  @override
  String mcpProbeQueued(int count) {
    return 'Queued $count';
  }

  @override
  String get mcpProbeStateRunning => 'running';

  @override
  String get mcpProbeStateIdle => 'idle';

  @override
  String mcpProbeToolsStatus(Object status) {
    return 'Tools $status';
  }

  @override
  String mcpProbeHealthStatus(Object status) {
    return 'Health $status';
  }

  @override
  String mcpProbeLastRun(Object time) {
    return 'Last $time';
  }

  @override
  String mcpProbeNextRun(Object time) {
    return 'Next $time';
  }

  @override
  String get mcpProbeControlsTitle => 'Probe Controls';

  @override
  String get mcpProbeForceProbe => 'Force Probe';

  @override
  String get mcpProbeStopProbing => 'Stop Probing';

  @override
  String get mcpProbeReloadServers => 'Reload Servers';

  @override
  String mcpProbeServerStatusTitle(int count) {
    return 'Server Probe Status ($count servers)';
  }

  @override
  String get mcpProbeNoServers => 'No servers';

  @override
  String get mcpProbeHealthHealthy => 'Healthy';

  @override
  String get mcpProbeHealthUnhealthy => 'Unhealthy';

  @override
  String get mcpProbeHealthChecking => 'Checking';

  @override
  String get mcpProbeHealthIdle => 'Idle';

  @override
  String get mcpProbeDisableServerTooltip => 'Disable probing';

  @override
  String get mcpProbeEnableServerTooltip => 'Enable probing';

  @override
  String get mcpProbeNoProbe => 'No probe';

  @override
  String mcpProbeToolCount(int count) {
    return '$count tools';
  }

  @override
  String get mcpProbeThisServer => 'Probe this server';

  @override
  String get mcpRelativeJustNow => 'just now';

  @override
  String mcpRelativeSecondsAgo(int seconds) {
    return '${seconds}s ago';
  }

  @override
  String mcpRelativeMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String mcpRelativeHoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String mcpRelativeDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String get mcpRelativeImminent => 'imminent';

  @override
  String mcpRelativeInSeconds(int seconds) {
    return 'in ${seconds}s';
  }

  @override
  String mcpRelativeInMinutes(int minutes) {
    return 'in ${minutes}m';
  }

  @override
  String mcpRelativeInHours(int hours) {
    return 'in ${hours}h';
  }

  @override
  String mcpRelativeInDays(int days) {
    return 'in ${days}d';
  }

  @override
  String get mcpKeywordIndexUpdateModeLabel => 'Keyword index update mode';

  @override
  String get mcpKeywordIndexUpdateModeBody =>
      'Controls how the MCP tool keyword inverted index is rebuilt. Cold-start: only loads the on-disk cache at boot; click \'Build keyword index\' to refresh. Interval: rebuild on a periodic schedule (value + unit) and fully overwrite the cache. Scheduled: rebuild once per day at a fixed time. The latter two share one system cron entry to avoid scheduler fragmentation.';

  @override
  String get mcpKeywordIndexUpdateModeColdStart => 'Cold-start';

  @override
  String get mcpKeywordIndexUpdateModeInterval => 'Interval';

  @override
  String get mcpKeywordIndexUpdateModeScheduled => 'Daily time';

  @override
  String get mcpKeywordIndexUpdateModeColdStartHint =>
      'Cold-start mode: only loads the on-disk keyword index at app boot; click \'Build keyword index\' to refresh manually. The system cron entry stays disabled.';

  @override
  String get mcpKeywordIndexIntervalValueLabel => 'Interval';

  @override
  String get mcpKeywordIndexIntervalUnitLabel => 'Unit';

  @override
  String get mcpKeywordIndexIntervalUnitMinute => 'Minute(s)';

  @override
  String get mcpKeywordIndexIntervalUnitHour => 'Hour(s)';

  @override
  String get mcpKeywordIndexIntervalUnitDay => 'Day(s)';

  @override
  String mcpKeywordIndexScheduledLabel(String time) {
    return 'Rebuild daily at $time';
  }

  @override
  String get mcpKeywordIndexScheduledPickAction => 'Pick time';

  @override
  String get commonClose => 'Close';

  @override
  String get commonRunInBackground => 'Run in background';

  @override
  String get mcpBuildKeywordIndex => 'Build keyword index';

  @override
  String get mcpKeywordIndexBuildTitle => 'Building keyword inverted index';

  @override
  String get mcpKeywordIndexBuildStarting => 'Preparing…';

  @override
  String mcpKeywordIndexBuildProgress(
    int idx,
    int count,
    Object server,
    int tools,
  ) {
    return '$idx/$count: $server ($tools tools scanned)';
  }

  @override
  String mcpKeywordIndexBuildSummary(
    int servers,
    int tools,
    int keys,
    Object sec,
  ) {
    return 'Indexed $servers servers, $tools tools, $keys keywords in ${sec}s';
  }

  @override
  String mcpKeywordIndexBuildSkipped(int n) {
    return 'Skipped $n servers without a ready tool catalog';
  }

  @override
  String get mcpKeywordIndexBuildFailed => 'Build failed:';

  @override
  String get mcpLazyLoadingModeLabel => 'MCP tool lazy loading';

  @override
  String get mcpLazyLoadingModeBody =>
      'Controls whether MCP tool descriptions are collapsed out of the system prompt: Off = always expanded; On = always collapsed and fetched on demand via ToolSearch; Auto collapses only when the estimated token cost exceeds the threshold.';

  @override
  String get mcpLazyLoadingModeDisabled => 'Off';

  @override
  String get mcpLazyLoadingModeAuto => 'Auto';

  @override
  String get mcpLazyLoadingModeEnabled => 'On';

  @override
  String get mcpLazyLoadingThresholdLabel => 'MCP tool compression threshold';

  @override
  String get mcpLazyLoadingThresholdBody =>
      'In Auto mode, lazy loading kicks in when the estimated total tokens of MCP tool descriptions exceeds this value.';

  @override
  String get mcpLazyLoadingThresholdSave => 'Save threshold';

  @override
  String get mcpLazyLoadingThresholdSaved =>
      'MCP lazy-loading threshold saved.';

  @override
  String get mcpLazyLoadingThresholdInvalid =>
      'Please enter an integer between 1000 and 1000000.';

  @override
  String get settingsHarnessToolSearchHistoryCapLabel =>
      'Harness ToolSearch history cap';

  @override
  String get settingsHarnessToolSearchHistoryCapBody =>
      'Maximum number of recent Harness phases for which the ToolSearch loaded-list dialog retains history. Older phases are evicted (LRU).';

  @override
  String settingsHarnessToolSearchHistoryCapValue(int cap) {
    return 'Currently keeping the last $cap phase(s)';
  }

  @override
  String settingsHarnessToolSearchHistoryCapRange(int min, int max) {
    return 'Range: $min–$max (default 8)';
  }

  @override
  String settingsHarnessToolSearchHistoryCapResetTooltip(int defaultCap) {
    return 'Reset to default ($defaultCap)';
  }

  @override
  String get harnessCliLoginNoOutputHint =>
      '[Hint] CLI has not produced output yet. It may be initializing, or waiting for browser-based authorization.\n';

  @override
  String harnessCliLoginTimedOut(int minutes) {
    return 'Login timed out after $minutes minutes. The process was stopped.';
  }

  @override
  String get harnessCliLoginTtyRequiredHint =>
      '[Hint] This CLI may require a real terminal (TTY) for interactive login.\nUse the \"Open in Terminal\" button below to complete login in the system terminal.\n';

  @override
  String harnessCliLoginStreamError(Object error) {
    return '[Stream error: $error]';
  }

  @override
  String harnessCliLoginFailedToStartProcess(Object message) {
    return 'Failed to start process: $message';
  }

  @override
  String harnessCliLoginOpenTerminalError(Object error) {
    return '[Error opening terminal: $error]';
  }

  @override
  String get harnessCliLoginStatusFailed => 'Failed to launch';

  @override
  String get harnessCliLoginStatusStarting => 'Starting login flow...';

  @override
  String get harnessCliLoginStatusFinished => 'Process finished';

  @override
  String harnessCliLoginStatusFinishedWithExit(int exitCode) {
    return 'Process finished · exit $exitCode';
  }

  @override
  String get harnessCliLoginStatusWaiting => 'Waiting for CLI interaction...';

  @override
  String harnessCliLoginTitle(Object name) {
    return '$name Login';
  }

  @override
  String get harnessCliLoginDescription =>
      'This dialog runs the CLI login flow in-app. The CLI may open your browser externally during authentication.';

  @override
  String get harnessCliLoginCopyCommandTooltip => 'Copy command';

  @override
  String get harnessCliLoginEmptyOutput => 'Waiting for CLI output...';

  @override
  String get harnessCliLoginInputLabel => 'Send input';

  @override
  String get harnessCliLoginInputHint =>
      'Type a reply and press Enter; leave empty to send Enter';

  @override
  String get harnessCliLoginSend => 'Send';

  @override
  String get harnessCliLoginSendEsc => 'Send Esc';

  @override
  String get harnessCliLoginOpenInTerminal => 'Open in Terminal';

  @override
  String get harnessCliInstallLogSuccess => '✓ Installed successfully';

  @override
  String harnessCliInstallLogSuccessWithPath(Object path) {
    return '✓ Installed successfully (path: $path)';
  }

  @override
  String harnessCliInstallLogFailureExitCode(int exitCode) {
    return '✗ Installation failed (exit code: $exitCode)';
  }

  @override
  String harnessCliInstallLogStartProcessFailed(Object message) {
    return '✗ Failed to start install process: $message';
  }

  @override
  String harnessCliInstallLogGenericError(Object error) {
    return '✗ Error: $error';
  }

  @override
  String get harnessCliInstallHintInstallNode =>
      '  → Install Node.js first: https://nodejs.org';

  @override
  String get harnessCliInstallHintRetryAdminButton =>
      '  → Click the \"Retry with Admin\" button below';

  @override
  String harnessCliInstallHintTrySudo(Object command) {
    return '  → Try: sudo $command';
  }

  @override
  String get harnessCliInstallHintCheckNetworkDocs =>
      '  → Check your network connection or see the official docs';

  @override
  String get harnessCliInstallHintInstallPipx =>
      '  → Install pipx first: https://pipx.pypa.io/stable/installation/';

  @override
  String get harnessCliInstallHintUsePipInstallUserAider =>
      '    Or use: pip install --user aider-chat';

  @override
  String get harnessCliInstallHintHomebrewNoSudo =>
      '  → Homebrew usually should not be installed with sudo; check directory permissions';

  @override
  String get harnessCliInstallHintHomebrewFix =>
      '  → Suggested fix: https://docs.brew.sh/FAQ#why-does-homebrew-say-sudo-is-not-allowed';

  @override
  String get harnessCliInstallHintInstallPython =>
      '  → Install Python first: https://www.python.org';

  @override
  String harnessCliInstallHintPipInstallUser(Object packageName) {
    return '  → Try: pip install --user $packageName';
  }

  @override
  String harnessCliInstallHintOfficialDocs(Object url) {
    return '  → Official docs: $url';
  }

  @override
  String get harnessCliInstallLogCancelled => '⚠ Installation was cancelled';

  @override
  String get harnessCliInstallWindowsAdminManual =>
      'Run manually in PowerShell with administrator privileges:';

  @override
  String harnessCliInstallAdminCommand(Object command) {
    return '> [Admin] $command';
  }

  @override
  String get harnessCliInstallAdminTimeout =>
      '✗ Admin authorization dialog timed out or failed to start; forcibly ended the osascript child process';

  @override
  String get harnessCliInstallUserCancelledAuth =>
      '⚠ Authorization was cancelled';

  @override
  String get harnessCliInstallAdminPermissionFailed =>
      '✗ Could not obtain administrator privileges';

  @override
  String harnessCliInstallPathMissingWarning(Object executable) {
    return '⚠ Installation completed, but $executable was not found in the current PATH';
  }

  @override
  String get harnessCliInstallRestartPathHint =>
      '  → Try restarting OpenHand or launching it from a terminal to load the new PATH';

  @override
  String get harnessCliInstallTimeoutManual =>
      '✗ Installation timed out (over 5 minutes). Run manually:';

  @override
  String harnessCliInstallOsascriptStartFailed(Object message) {
    return '✗ Failed to start osascript: $message';
  }

  @override
  String get harnessCliInstallLinuxSudoManual =>
      'Run manually in a terminal (root privileges required):';

  @override
  String get harnessCliInstallStatusInstalling => 'Installing...';

  @override
  String get harnessCliInstallStatusSuccess => 'Installed successfully';

  @override
  String get harnessCliInstallStatusCancelled => 'Cancelled';

  @override
  String get harnessCliInstallStatusFailed => 'Installation failed';

  @override
  String harnessCliInstallTitle(Object name) {
    return 'Install $name';
  }

  @override
  String get harnessCliInstallCopyDocUrl => 'Copy Doc URL';

  @override
  String get harnessCliInstallCancel => 'Cancel install';

  @override
  String get harnessCliInstallRetryAdmin => 'Retry with Admin';

  @override
  String get harnessCliInstallDoneContinue => 'Done, continue';

  @override
  String get settingsToolSearchReplayCancelWindowLabel =>
      'Replay cancel window';

  @override
  String get settingsToolSearchReplayCancelWindowBody =>
      'How long the snackbar waits before sending; press Cancel inside this window to discard.';

  @override
  String settingsToolSearchReplayCancelWindowValue(int seconds) {
    return 'Window: $seconds s';
  }

  @override
  String settingsToolSearchReplayCancelWindowRange(int min, int max) {
    return 'Range: $min–$max s (default 3)';
  }

  @override
  String settingsToolSearchReplayCancelWindowResetTooltip(int defaultSeconds) {
    return 'Reset to default ($defaultSeconds s)';
  }

  @override
  String get mcpLazyLoadingHowItWorks =>
      'When lazy loading is active, MCP tool descriptions are folded into a name index. The built-in ToolSearch tool fetches full JSON Schema on demand via three query forms:\n• select:NAME (direct, space-separated for multi-select)\n• keyword (scored against name/description)\n• +KEYWORD (required term to filter noise)\nAfter a match, call ToolSearch with the exact tool_name and schema-matching arguments. The native tool list stays fixed to preserve prompt-cache reuse.';

  @override
  String get settingsGeneralSubtitle =>
      'Manage theme, language, and core application information.';

  @override
  String get settingsAiSubtitle =>
      'Manage chat models, authentication, and protocol adapters.';

  @override
  String get settingsActiveToolCallsTitle => 'Active tool calls';

  @override
  String get settingsActiveToolCallsBody =>
      'Live view of every dispatched tool call: PID, kind, owning session, and elapsed time. Press Stop to terminate just that call.';

  @override
  String get settingsActiveToolCallsEmpty =>
      'No tool calls are currently running.';

  @override
  String get settingsActiveToolCallsCancel => 'Stop';

  @override
  String get settingsActiveToolKindBuiltin => 'Built-in';

  @override
  String get settingsActiveToolKindMcp => 'MCP';

  @override
  String get settingsActiveToolKindSkill => 'Skill';

  @override
  String get settingsActiveToolSessionLabel => 'session';

  @override
  String get settingsToolHardeningTitle => 'Tool Hardening Parameters';

  @override
  String get settingsToolHardeningBody =>
      'Subprocess graceful shutdown duration, bash output cap, and concurrent tool-call limit.';

  @override
  String get settingsSubprocessGracefulShutdownLabel =>
      'Subprocess graceful shutdown (ms)';

  @override
  String get settingsSubprocessGracefulShutdownBody =>
      'How long to wait between SIGTERM and SIGKILL when cancelling a tool. Larger values are gentler but make Stop feel slower. Range 100–5000.';

  @override
  String get settingsBashOutputMaxBytesLabel => 'Bash capture limit (chars)';

  @override
  String get settingsBashOutputMaxBytesBody =>
      'Per-call cap for combined stdout+stderr captured by the bash tool. Output beyond is mid-truncated, keeping head and tail. Range 16000–4000000.';

  @override
  String get settingsMaxConcurrentToolsLabel => 'Concurrent tool calls';

  @override
  String get settingsMaxConcurrentToolsBody =>
      'Maximum tool calls dispatched in parallel within a session. Range 1–64.';

  @override
  String get settingsToolHardeningInvalid =>
      'Please enter an integer within range';

  @override
  String get settingsSkillsSubtitle =>
      'Manage the local skills directory, template creation, and installed skills.';

  @override
  String get settingsMemorySubtitle =>
      'Manage the user-memory switch and the persistence file path.';

  @override
  String get settingsPersistenceInvalidTitle => 'Settings Data Is Invalid';

  @override
  String get settingsPersistenceInvalidBody =>
      'The database record cannot be parsed. Safe defaults are shown without overwriting the original data.';

  @override
  String get settingsPersistenceLoadFailedTitle => 'Settings Read Failed';

  @override
  String get settingsPersistenceLoadFailedBody =>
      'The local database could not be read. Defaults are shown temporarily and saving is paused to protect existing data.';

  @override
  String get settingsPersistenceSaveFailedTitle => 'Settings Save Failed';

  @override
  String get settingsPersistenceSaveFailedBody =>
      'Writing the settings database failed. The UI was rolled back to the last valid configuration. Check database access and disk state.';

  @override
  String get settingsPersistenceDismiss => 'Dismiss';

  @override
  String get settingsAnimationRestoreDefaultsTitle =>
      'Restore Animation Defaults';

  @override
  String get settingsAnimationRestoreDefaultsSubtitle =>
      'Reset entrance/exit style, duration, and easing curve for dialog, menu, page/module, workspace panel, chip, and list item animations to OpenHand\'s recommended defaults in one click.';

  @override
  String get settingsAnimationRestoreDefaultsButton => 'Restore Defaults';

  @override
  String get settingsAnimationRestoreConfirmTitle =>
      'Restore default animations?';

  @override
  String get settingsAnimationRestoreConfirmMessage =>
      'Dialog, menu, page/module, workspace panel, chip, and list item animations will all be reset to defaults. Customized values will be overwritten and this cannot be undone.';

  @override
  String get settingsAnimationRestoreConfirm => 'Restore';

  @override
  String get settingsAnimationRestoreSuccess => 'Animation defaults restored';

  @override
  String get settingsDialogAnimationTitle => 'Dialog Animation';

  @override
  String get settingsDialogAnimationSubtitle =>
      'Configure entrance/exit animation style, duration, and easing curve for all dialogs.';

  @override
  String get settingsMenuAnimationTitle => 'Menu Animation';

  @override
  String get settingsMenuAnimationSubtitle =>
      'Configure entrance/exit animation style, duration, and easing curve for popup menus and context menus.';

  @override
  String get settingsPanelAnimationTitle => 'Workspace Panel Animation';

  @override
  String get settingsPanelAnimationSubtitle =>
      'Configure entrance/exit animation style, duration, and easing curve for workspace panel transitions, such as left navigation/file explorer and right conversation/code editor switches. Settings, MCP, Memory, and other right-side module page switches are controlled by Page Animation.';

  @override
  String get settingsPageAnimationTitle => 'Page / Module Animation';

  @override
  String get settingsPageAnimationSubtitle =>
      'Configure entrance/exit animation style, duration, and easing curve for right-side main content module switches, including Workspace, Settings, MCP, Memory, Hooks, Crons, Skills, and Automations.';

  @override
  String get settingsChipAnimationTitle => 'Chip Animation';

  @override
  String get settingsChipAnimationSubtitle =>
      'Configure entrance/exit animation style, duration, and easing curve for all removable chips (selected skill, attachments, project references, queued messages, editing pill, etc.). Tapping × plays the exit animation before the chip is removed from layout.';

  @override
  String get settingsListItemAnimationTitle => 'List Item Animation';

  @override
  String get settingsListItemAnimationSubtitle =>
      'Configure entrance animation style and duration for list items including MCP servers, memory entries, instruction cards, sidebar threads, and tool-call cards. Set to \"None\" to disable list-item entrance animation entirely.';

  @override
  String get settingsAnimationEnter => 'Enter';

  @override
  String get settingsAnimationExit => 'Exit';

  @override
  String get settingsAnimationDuration => 'Duration';

  @override
  String get settingsAnimationCurve => 'Curve';

  @override
  String get dialogAnimationStyleNone => 'None';

  @override
  String get dialogAnimationStyleFade => 'Fade';

  @override
  String get dialogAnimationStyleFadeScale => 'Fade & Scale';

  @override
  String get dialogAnimationStyleSlideUp => 'Slide Up';

  @override
  String get dialogAnimationStyleSlideDown => 'Slide Down';

  @override
  String get dialogAnimationStyleSlideLeft => 'Slide Left';

  @override
  String get dialogAnimationStyleSlideRight => 'Slide Right';

  @override
  String get dialogAnimationStyleExpand => 'Expand';

  @override
  String get dialogAnimationStyleRotateScale => 'Rotate & Scale';

  @override
  String get dialogAnimationStyleElastic => 'Elastic';

  @override
  String get dialogAnimationStyleSpringScale => 'Spring Scale';

  @override
  String get dialogAnimationStyleFlipX => 'Flip X';

  @override
  String get dialogAnimationCurveEaseInOut => 'Ease In-Out';

  @override
  String get dialogAnimationCurveEaseOut => 'Ease Out';

  @override
  String get dialogAnimationCurveEaseOutCubic => 'Ease Out Cubic';

  @override
  String get dialogAnimationCurveEaseInOutCubicEmphasized => 'Cubic Emphasized';

  @override
  String get dialogAnimationCurveElasticOut => 'Elastic Out';

  @override
  String get dialogAnimationCurveBounceOut => 'Bounce Out';

  @override
  String get dialogAnimationCurveDecelerate => 'Decelerate';

  @override
  String get commonOptional => 'Optional';

  @override
  String get cronScriptTypeCommand => 'Command';

  @override
  String get cronScriptTypeScript => 'Script';

  @override
  String get cronScriptTypeAgent => 'Agent';

  @override
  String get cronJobStatusRunning => 'Running';

  @override
  String get cronJobStatusPaused => 'Paused';

  @override
  String get cronJobStatusFailed => 'Failed';

  @override
  String get cronJobStatusError => 'Error';

  @override
  String get cronJobStatusIdle => 'Idle';

  @override
  String get cronNotifyTypeNone => 'None';

  @override
  String get cronNotifyTypeLog => 'Log Only';

  @override
  String get cronNotifyTypeSystem => 'System Notification';

  @override
  String get cronNotifyTypeAppNotification => 'In-App Notification';

  @override
  String get cronNotifySeverityInfo => 'Info';

  @override
  String get cronNotifySeveritySuccess => 'Success';

  @override
  String get cronNotifySeverityWarning => 'Warning';

  @override
  String get cronNotifySeverityError => 'Error';

  @override
  String get cronNotifySeverityCritical => 'Critical';

  @override
  String get cronParserFieldCountError =>
      'Cron expression must have exactly 5 fields (min hour dom mon dow)';

  @override
  String get cronParserFieldMinute => 'Minute';

  @override
  String get cronParserFieldHour => 'Hour';

  @override
  String get cronParserFieldDayOfMonth => 'Day of month';

  @override
  String get cronParserFieldDayOfMonthShort => 'DoM';

  @override
  String get cronParserFieldMonth => 'Month';

  @override
  String get cronParserFieldDayOfWeek => 'Day of week';

  @override
  String get cronParserFieldDayOfWeekShort => 'DoW';

  @override
  String cronParserInvalidField(String field, String value) {
    return 'Invalid $field field \"$value\"';
  }

  @override
  String get cronsViewDescription =>
      'Configure and manage scheduled tasks. Supports cron expression scheduling, timeout control, auto-retry, and execution history.';

  @override
  String get cronsNewCronJob => 'New Cron Job';

  @override
  String get cronsEditCronJob => 'Edit Cron Job';

  @override
  String get cronsDeleteCronJobTitle => 'Delete Cron Job';

  @override
  String cronsDeleteCronJobMessage(String name) {
    return 'Delete \"$name\"? This cannot be undone. Execution history will also be removed.';
  }

  @override
  String get cronsEmptyTitle => 'No cron jobs configured yet';

  @override
  String get cronsEmptyBody => 'Click \"New Cron Job\" above to get started.';

  @override
  String get cronsCronExpressionTooltip => 'Cron expression';

  @override
  String get cronsTimeoutTooltip => 'Timeout';

  @override
  String get cronsRetryCountTooltip => 'Retry count';

  @override
  String get cronsMcpKeywordIndexLockedTooltip =>
      'Controlled by Settings -> MCP -> Keyword index update mode';

  @override
  String get cronsRunOnceNow => 'Run once now';

  @override
  String get cronsHistory => 'History';

  @override
  String cronsLastRunAt(String time) {
    return 'Last: $time';
  }

  @override
  String get cronsFieldName => 'Name';

  @override
  String get cronsFieldNameHint => 'e.g. Daily Backup';

  @override
  String get cronsFieldDescription => 'Description';

  @override
  String get cronsFieldType => 'Type';

  @override
  String get cronsFieldScriptFilePath => 'Script File Path';

  @override
  String get cronsFieldScriptFilePathHint => 'Select a .sh / .ps1 / .bat file';

  @override
  String get cronsBrowse => 'Browse';

  @override
  String get cronsFieldCommand => 'Command';

  @override
  String get cronsFieldCommandHintWindows => 'Enter PowerShell / BAT command';

  @override
  String get cronsFieldCommandHintShell => 'Enter shell command';

  @override
  String get cronsCronSchedule => 'Cron Schedule';

  @override
  String get cronsCronScheduleHelper =>
      'Seconds field frozen at 0. Minimum granularity: minute. Format: min hour dom mon dow';

  @override
  String get cronsTimeoutSeconds => 'Timeout (s)';

  @override
  String get cronsRetries => 'Retries';

  @override
  String get cronsMaxRetryDelaySeconds => 'Max retry delay (s)';

  @override
  String get cronsRunAsUser => 'Run As User';

  @override
  String get cronsDefaultCurrentUser => 'Default (current user)';

  @override
  String get cronsDefault => 'Default';

  @override
  String get cronsTagsCommaSeparated => 'Tags (comma-separated)';

  @override
  String get cronsTagsHint => 'e.g. backup, cleanup';

  @override
  String get cronsWorkingDirectory => 'Working Directory';

  @override
  String get cronsWorkingDirectoryHint => 'Optional, defaults to app dir';

  @override
  String get cronsEnvironmentVariables => 'Environment Variables';

  @override
  String get cronsEnvironmentVariablesHint => 'One per line, format: KEY=VALUE';

  @override
  String get cronsExecutionContextCollection => 'Execution Context Collection';

  @override
  String get cronsCollectAppMetadata => 'Capture app metadata';

  @override
  String get cronsCollectAppMetadataSubtitle =>
      'Capture app version, PID, executable path, etc.';

  @override
  String get cronsCollectHostMetadata => 'Capture host metadata';

  @override
  String get cronsCollectHostMetadataSubtitle =>
      'Capture OS version, host name, CPU cores, etc.';

  @override
  String get cronsCollectEnvironmentSnapshot => 'Capture environment snapshot';

  @override
  String get cronsCollectEnvironmentSnapshotSubtitle =>
      'Capture effective runtime environment variables (may include sensitive data).';

  @override
  String get cronsSensitive => 'Sensitive';

  @override
  String get cronsNotificationSettings => 'Notification Settings';

  @override
  String get cronsTestNotification => 'Test Notification';

  @override
  String get cronsTestSuccessNotification => 'Test success notification';

  @override
  String get cronsTestFailureNotification => 'Test failure notification';

  @override
  String get cronsTestTimeoutNotification => 'Test timeout notification';

  @override
  String get cronsTestAllNotifications => 'Test all (sequential)';

  @override
  String get cronsNotificationSettingsHelper =>
      'Each event can be configured independently for channel, severity, sound, and vibration.';

  @override
  String get cronsOnSuccess => 'On Success';

  @override
  String get cronsOnFailure => 'On Failure';

  @override
  String get cronsOnTimeout => 'On Timeout';

  @override
  String get cronsEnabled => 'Enabled';

  @override
  String get cronsCustomNotificationMessageHint => 'Custom message (optional)';

  @override
  String get cronsVibrationUnsupportedHint =>
      'Vibration is not supported on this platform and will be ignored.';

  @override
  String get cronsValidationNameRequired => 'Enter a cron job name.';

  @override
  String get cronsValidationScriptRequired => 'Select a script file.';

  @override
  String get cronsValidationCommandRequired => 'Enter a command.';

  @override
  String cronsValidationInvalidEnvironment(String lines) {
    return 'Invalid environment variable format on line(s) $lines. Use KEY=VALUE.';
  }

  @override
  String get cronsNotificationSequentialStartTitle =>
      'Starting Sequential Test';

  @override
  String get cronsNotificationSequentialStartBody =>
      'Running success, failure, and timeout notification tests in sequence.';

  @override
  String get cronsNotificationVibrationIgnoredTitle => 'Vibration Ignored';

  @override
  String get cronsNotificationSequentialVibrationIgnoredBody =>
      'Vibration is not supported on this platform and was ignored during sequential test.';

  @override
  String get cronsNotificationSequentialCompletedTitle =>
      'Sequential Test Completed';

  @override
  String get cronsNotificationSequentialCompletedBody =>
      'Completed success, failure, and timeout notification tests.';

  @override
  String get cronsNotificationScenarioSuccess => 'Success';

  @override
  String get cronsNotificationScenarioFailure => 'Failure';

  @override
  String get cronsNotificationScenarioTimeout => 'Timeout';

  @override
  String get cronsNotificationScenarioAll => 'All';

  @override
  String cronsNotificationTestTitle(String label) {
    return 'Cron Notification Test - $label';
  }

  @override
  String get cronsNotificationTestDefaultBodySuccess =>
      'Notification test message for success.';

  @override
  String get cronsNotificationTestDefaultBodyFailure =>
      'Notification test message for failure.';

  @override
  String get cronsNotificationTestDefaultBodyTimeout =>
      'Notification test message for timeout.';

  @override
  String get cronsNotificationNoEmitBody =>
      'Current setting is None or Log Only, so no notification is emitted.';

  @override
  String get cronsSystemNotificationUnavailableTitle =>
      'System Notification Unavailable';

  @override
  String get cronsSystemNotificationFallbackBody =>
      'System notification failed; fallback to in-app notification.';

  @override
  String get cronsNotificationVibrationIgnoredBody =>
      'Vibration is not supported on this platform and was ignored.';

  @override
  String get cronsUnknownPlatform => 'Unknown platform';

  @override
  String get cronsToggleOn => 'On';

  @override
  String get cronsToggleOff => 'Off';

  @override
  String get cronsSupportBestEffortSystemSound =>
      'Supported (best effort via system sound)';

  @override
  String get cronsSupportSupported => 'Supported';

  @override
  String get cronsSupportNotSupportedOnPlatform =>
      'Not supported on this platform';

  @override
  String get cronsSupportNotSupportedWillBeIgnored =>
      'Not supported (will be ignored)';

  @override
  String get cronsSoundLabel => 'Sound';

  @override
  String get cronsVibrationLabel => 'Vibration';

  @override
  String get cronsPlatformLabel => 'Platform';

  @override
  String get cronsSupportLabel => 'Support';

  @override
  String get cronsExecutionHistoryTitle => 'Scheduled Task Execution History';

  @override
  String get cronsClearAllExecutionHistory => 'Clear all execution history';

  @override
  String get cronsNoExecutionRecords => 'No execution records yet';

  @override
  String get cronsClearExecutionHistoryTitle => 'Clear Execution History';

  @override
  String cronsClearExecutionHistoryMessage(String name) {
    return 'Clear all execution history for \"$name\"? This cannot be undone.';
  }

  @override
  String get cronsClear => 'Clear';

  @override
  String get cronsDeleteExecutionRecordTitle => 'Delete Execution Record';

  @override
  String get cronsDeleteExecutionRecordMessage =>
      'Delete this execution record?';

  @override
  String get cronsExecutionStatusSuccess => 'Success';

  @override
  String get cronsExecutionStatusFailed => 'Failed';

  @override
  String get cronsExecutionStatusTimedOut => 'Timed Out';

  @override
  String get cronsExecutionStatusRunning => 'Running';

  @override
  String get cronsExecutionStatusKilled => 'Killed';

  @override
  String get cronsTriggerManual => 'Manual';

  @override
  String get cronsTriggerScheduled => 'Scheduled';

  @override
  String get cronsDeleteThisRecord => 'Delete this record';

  @override
  String get cronsRetryAttempt => 'Retry Attempt';

  @override
  String get cronsRunAs => 'Run As';

  @override
  String get cronsWorkingDir => 'Working Dir';

  @override
  String get cronsScriptEnvironmentOverrides => 'Script Environment Overrides:';

  @override
  String get cronsEnvironmentSnapshot => 'Environment Snapshot:';

  @override
  String get cronsErrorReason => 'Error:';

  @override
  String get cronsStdout => 'stdout:';

  @override
  String get cronsStderr => 'stderr:';

  @override
  String get cronsExecutionContext => 'Execution Context:';

  @override
  String get cronsHermesTalkerReportTitle => 'Hermes Talker Report';

  @override
  String get cronsHermesNoEligibleSessions =>
      'No eligible sessions were actually learned this tick.';

  @override
  String cronsHermesAffectedSessions(int count) {
    return 'Affected Sessions ($count)';
  }

  @override
  String cronsHermesStatsLine(
    int scanned,
    int triggered,
    int skipped,
    int errors,
  ) {
    return 'scanned $scanned · triggered $triggered · skipped $skipped · errors $errors';
  }

  @override
  String get cronsHermesUntitledSession => '(untitled session)';

  @override
  String cronsHermesMemoryUpdates(int count) {
    return 'memory +$count';
  }

  @override
  String cronsHermesMemoryErrors(int count) {
    return 'memory err $count';
  }

  @override
  String cronsHermesSkillUpdates(int count) {
    return 'skill +$count';
  }

  @override
  String cronsHermesSkillErrors(int count) {
    return 'skill err $count';
  }

  @override
  String cronsHermesProfileChanges(int count) {
    return 'profile $count';
  }

  @override
  String cronsHermesToolRounds(int count) {
    return 'rounds $count';
  }

  @override
  String get cronsHermesModelLabel => 'model';

  @override
  String get cronsHermesProviderLabel => 'provider';

  @override
  String get cronsHermesTerminatedLabel => 'terminated';

  @override
  String get cronsHermesUserProfileChanges => 'User profile changes';

  @override
  String get cronsHermesMemoryChanges => 'Memory changes';

  @override
  String get cronsHermesSkillChanges => 'Skill changes';

  @override
  String get cronsHermesAiReasoningOnScene => 'AI reasoning on scene';

  @override
  String get cronsHermesAiResponseOnScene => 'AI response on scene';

  @override
  String get cronsHermesNoFurtherDetails => 'No further details.';

  @override
  String get cronsHermesStatusError => 'error';

  @override
  String get cronsHermesStatusSkipped => 'skipped';

  @override
  String get cronsHermesStatusOk => 'ok';

  @override
  String get cronsHermesChangeBefore => 'before';

  @override
  String get cronsHermesChangeAfter => 'after';

  @override
  String get cronsHermesChangeValue => 'value';

  @override
  String get cronsHermesChangeSource => 'source';

  @override
  String get cronsHermesChangeReason => 'reason';

  @override
  String get cronsHermesChangeMetadata => 'metadata';

  @override
  String get cronsHermesChangeError => 'error';

  @override
  String get cronsCollapse => 'Collapse';

  @override
  String get cronsExpand => 'Expand';

  @override
  String get aiModelAdd => 'Add Provider';

  @override
  String get aiModelsEmptyTitle => 'No model providers yet';

  @override
  String get aiModelsEmptyBody =>
      'Add at least one model provider configuration here, and the thread composer will reuse it directly.';

  @override
  String get aiModelDialogCreateTitle => 'Add Model Provider';

  @override
  String get aiModelDialogEditTitle => 'Edit Model Provider';

  @override
  String get aiModelBaseUrl => 'Base URL';

  @override
  String get aiModelBaseUrlRequired => 'Enter a base URL.';

  @override
  String get aiModelBaseUrlInvalid => 'Enter a valid base URL.';

  @override
  String get aiModelOfficialWebsiteUrl => 'Website URL (optional)';

  @override
  String get aiModelOfficialWebsiteUrlHint => 'https://example.com';

  @override
  String get aiModelOfficialWebsiteUrlInvalid => 'Enter a valid website URL.';

  @override
  String get aiModelOpenWebsiteFailure => 'Could not open website.';

  @override
  String get aiModelOpenWebsiteTooltip => 'Open website';

  @override
  String get aiModelAuthScheme => 'Auth Scheme';

  @override
  String get aiModelToken => 'Token';

  @override
  String get aiModelProtocol => 'Protocol';

  @override
  String get aiModelSaveSuccess => 'Model provider configuration saved.';

  @override
  String get aiModelDeleteConfirmTitle => 'Delete Model Provider';

  @override
  String get aiModelDeleteConfirmBody =>
      'Delete this model provider configuration?';

  @override
  String get aiModelDeleteSuccess => 'Model provider configuration deleted.';

  @override
  String get aiModelMoveUp => 'Move Up';

  @override
  String get aiModelMoveDown => 'Move Down';

  @override
  String get aiModelSelected => 'Active model provider';

  @override
  String get aiModelNoToken => 'No token configured';

  @override
  String get aiModelTest => 'Test';

  @override
  String get aiModelTesting => 'Testing';

  @override
  String aiModelTestSuccess(String modelName) {
    return '$modelName passed the test.';
  }

  @override
  String aiModelTestFailure(String modelName, String reason) {
    return '$modelName test failed: $reason';
  }

  @override
  String get aiModelSelectionRequired =>
      'Add and select an AI model provider in Settings first.';

  @override
  String get aiModelScanButton => 'Scan Models';

  @override
  String get aiModelScanning => 'Scanning available models…';

  @override
  String get aiModelAvailableModels => 'Available Models';

  @override
  String get aiModelManualIdHint => 'Add model ID manually';

  @override
  String get aiModelManualIdAdd => 'Add';

  @override
  String aiModelCount(int count) {
    return '$count models';
  }

  @override
  String get chatModelButton => 'Choose Model';

  @override
  String get aiAuthNone => 'None';

  @override
  String get aiAuthBearer => 'Bearer';

  @override
  String get aiAuthToken => 'Token';

  @override
  String get aiAuthApiKey => 'API Key';

  @override
  String get aiProtocolOpenAi => 'OpenAI';

  @override
  String get aiProtocolDots => 'Dots (Xiaohongshu)';

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
  String get aiProtocolQwen => 'Qwen';

  @override
  String get aiProtocolSeed => 'Seed (Doubao)';

  @override
  String get aiProtocolStepFun => 'StepFun';

  @override
  String get aiProtocolMinimax => 'MiniMax';

  @override
  String get aiProtocolLongCat => 'LongCat';

  @override
  String get aiProtocolAgnes => 'Agnes';

  @override
  String get aiProtocolJoyCode => 'JoyCode';

  @override
  String get aiProtocolWenxin => 'Wenxin / ERNIE';

  @override
  String get aiProtocolMeta => 'Meta AI / Llama';

  @override
  String get aiProtocolMimo => 'MIMO';

  @override
  String get aiProtocolHunyuan => 'Hunyuan';

  @override
  String get skillsPageTitle => 'Skills';

  @override
  String get skillsPageSubtitle =>
      'Give OpenHand stronger extensibility with a unified view of installed local skills and templates.';

  @override
  String get skillsSearchHint => 'Search skills';

  @override
  String get skillsRefresh => 'Refresh';

  @override
  String get skillsOpenDirectory => 'Open Directory';

  @override
  String get skillsImport => 'Import Skill';

  @override
  String get skillsNewSkill => 'New Skill';

  @override
  String get skillsEmptyTitle => 'No skills installed yet';

  @override
  String get skillsEmptyBody =>
      'No SKILL.md files were found in the current skills directory. Create a template or switch to an existing skills directory.';

  @override
  String get skillsNoResultsTitle => 'No matching skills found';

  @override
  String get skillsNoResultsBody =>
      'Try a different search keyword or clear the search to see all skills again.';

  @override
  String get skillTemplateCreated => 'Skill created';

  @override
  String get skillOperationFailed =>
      'The skill action failed. Please try again.';

  @override
  String get skillsImportSuccess => 'Skill imported';

  @override
  String get skillsEdit => 'Edit Skill';

  @override
  String get skillsDelete => 'Delete Skill';

  @override
  String get skillsPreviewClose => 'Close';

  @override
  String get skillsEditorLabel => 'SKILL.md Content';

  @override
  String get skillsCreateDialogTitle => 'Create Skill';

  @override
  String get skillsCreateNameLabel => 'Skill Name';

  @override
  String get skillsCreateNameRequired => 'Enter the skill name.';

  @override
  String get skillsCreateIconLabel => 'Skill Icon';

  @override
  String get skillsCreateIconHint => 'Choose an emoji or a local image.';

  @override
  String get skillsCreateIconRequired => 'Choose an icon.';

  @override
  String get skillsCreateIconChoose => 'Choose Emoji';

  @override
  String get skillsCreateIconChange => 'Change';

  @override
  String get skillsCreateImageChoose => 'Choose Image';

  @override
  String get skillsCreateImageChange => 'Replace Image';

  @override
  String get skillsCreateImageSelected => 'Local image selected';

  @override
  String get skillsCreateDescriptionLabel => 'Short Description';

  @override
  String get skillsCreateDescriptionRequired => 'Enter the short description.';

  @override
  String get skillsCreateContentRequired => 'Enter the SKILL.md content.';

  @override
  String get imageEditorTitle => 'Edit Image';

  @override
  String get imageEditorCropHint =>
      'Drag the image to reposition the square crop area, then adjust zoom, rotation, brightness, and contrast.';

  @override
  String get imageEditorZoomLabel => 'Zoom';

  @override
  String get imageEditorBrightnessLabel => 'Brightness';

  @override
  String get imageEditorContrastLabel => 'Contrast';

  @override
  String get imageEditorRotateLeft => 'Rotate Left';

  @override
  String get imageEditorRotateRight => 'Rotate Right';

  @override
  String get imageEditorReset => 'Reset';

  @override
  String get imageEditorLoadFailed => 'Unable to load the selected image.';

  @override
  String get imageEditorProcessFailed =>
      'Unable to process the selected image.';

  @override
  String get imageEditorSectionColor => 'Color (temperature / tint / gamma)';

  @override
  String get imageEditorSectionSplitToning => 'Split toning (HSL)';

  @override
  String get imageEditorSectionDetail =>
      'Detail (clarity / sharpness / denoise / grain)';

  @override
  String get imageEditorSectionEffects =>
      'Effects (dispersion / distortion / vignette)';

  @override
  String get imageEditorSectionWatermark => 'Text watermark / mark';

  @override
  String get imageEditorTemperatureLabel => 'Temperature';

  @override
  String get imageEditorTintLabel => 'Tint shift';

  @override
  String get imageEditorGammaLabel => 'Gamma (curve)';

  @override
  String get imageEditorShadowHueLabel => 'Shadow hue';

  @override
  String get imageEditorShadowStrengthLabel => 'Shadow strength';

  @override
  String get imageEditorHighlightHueLabel => 'Highlight hue';

  @override
  String get imageEditorHighlightStrengthLabel => 'Highlight strength';

  @override
  String get imageEditorClarityLabel => 'Clarity';

  @override
  String get imageEditorSharpnessLabel => 'Sharpness';

  @override
  String get imageEditorDenoiseLabel => 'Denoise';

  @override
  String get imageEditorGrainLabel => 'Grain';

  @override
  String get imageEditorDispersionLabel => 'Dispersion';

  @override
  String get imageEditorDistortLabel =>
      'Distortion (positive bulges / negative stretches)';

  @override
  String get imageEditorWatermarkTextLabel => 'Watermark text';

  @override
  String get imageEditorWatermarkTextHint =>
      'Enter text to overlay (leave empty to skip)';

  @override
  String get imageEditorWatermarkSizeLabel => 'Text size';

  @override
  String get imageEditorWatermarkOpacityLabel => 'Opacity';

  @override
  String get imageEditorWatermarkPositionLabel => 'Position';

  @override
  String get imageEditorAdvancedApplyHint =>
      'Adjustments in expanded panels are applied to the original image when you save.';

  @override
  String get skillsEditorSave => 'Save';

  @override
  String get skillsEditorCancel => 'Cancel';

  @override
  String get skillsEditSuccess => 'Skill content saved';

  @override
  String get skillsDeleteConfirmTitle => 'Delete Skill';

  @override
  String get skillsDeleteConfirmBody =>
      'Deleting will permanently remove the skill directory and its SKILL.md content.';

  @override
  String get skillsDeleteConfirmAction => 'Delete';

  @override
  String get skillsDeleteSuccess => 'Skill deleted';

  @override
  String get skillsStorageSectionBody =>
      'Configure the local directory that OpenHand scans for skills. By default it uses ~/.openhand/skills and creates it when needed.';

  @override
  String get skillsStorageDefaultPath => 'Default Path';

  @override
  String get skillsStorageCurrentPath => 'Current Path';

  @override
  String get skillsStorageSave => 'Save Location';

  @override
  String get skillsStorageBrowse => 'Choose Directory';

  @override
  String get skillsStorageReset => 'Restore Default';

  @override
  String get skillsStorageOpen => 'Open Location';

  @override
  String get skillsStorageStatusError => 'Failed to read the skills directory';

  @override
  String get skillsPathSaved => 'The skills storage location has been updated';

  @override
  String get instructionPageTitle => 'Instructions';

  @override
  String get instructionPageSubtitle =>
      'Manage reusable prompt fragments. Enabled instructions are injected into every thread system prompt in the current order and shown above the composer as chips that can be toggled for a single send.';

  @override
  String get instructionRefresh => 'Refresh';

  @override
  String get instructionNewEntry => 'New Instruction';

  @override
  String get instructionEmptyTitle => 'No instructions yet';

  @override
  String get instructionEmptyBody =>
      'Create the first reusable instruction and OpenHand will keep it in the local instruction store.';

  @override
  String get instructionLoadFailedTitle => 'Instruction Store Failed to Load';

  @override
  String get instructionDeleteConfirmTitle => 'Delete Instruction';

  @override
  String get instructionDeleteConfirmBody =>
      'Delete this instruction? This action cannot be undone.';

  @override
  String get instructionEnabledStatus => 'Enabled and injected';

  @override
  String get instructionDisabledStatus => 'Disabled';

  @override
  String get instructionApplyToChipLabel => 'Apply to';

  @override
  String get instructionNotesChipLabel => 'Notes';

  @override
  String get instructionDialogCreateTitle => 'New Instruction';

  @override
  String get instructionDialogEditTitle => 'Edit Instruction';

  @override
  String get instructionEnabledLabel => 'Enabled';

  @override
  String get instructionEnabledBody =>
      'Inject this instruction into the active prompt chain.';

  @override
  String get instructionNameField => 'Name *';

  @override
  String get instructionNameRequired => 'Enter a name.';

  @override
  String get instructionDescriptionField => 'Description';

  @override
  String get instructionVersionField => 'Version';

  @override
  String get instructionApplyToField =>
      'Apply to (describe when this instruction loads)';

  @override
  String get instructionTaskTypesField =>
      'Trigger task types (comma-separated)';

  @override
  String get instructionKeywordsField => 'Trigger keywords (comma-separated)';

  @override
  String get instructionNotesField => 'Notes (one per line)';

  @override
  String get instructionBodyField => 'Instruction body * (Markdown)';

  @override
  String get instructionBodyRequired => 'Enter the instruction body.';

  @override
  String get instructionCreateAction => 'Create';

  @override
  String get instructionSaveFailed =>
      'Save failed. Check that required fields are not empty.';

  @override
  String get memoryPageTitle => 'Memory';

  @override
  String get memoryPageSubtitle =>
      'Manage editable user memories stored in the local database.';

  @override
  String get memoryRefresh => 'Refresh';

  @override
  String get memoryNewEntry => 'New Memory';

  @override
  String get memoryEmptyTitle => 'No user memories yet';

  @override
  String get memoryEmptyBody =>
      'Add a user memory and OpenHand will persist it in the local database.';

  @override
  String get memoryLoadFailedTitle => 'Failed to load memory data';

  @override
  String get memoryLoadFailedBody =>
      'Memory data is invalid or unavailable. Repair or clear the storage, then retry.';

  @override
  String get memoryQuotaRecoveryTitle => 'Memory storage is over quota';

  @override
  String get memoryQuotaRecoveryBody =>
      'A bounded snapshot is shown. Delete entries or reduce their content until usage is within limits; new entries are disabled.';

  @override
  String get memoryOperationFailed =>
      'The memory action failed. Please try again.';

  @override
  String get memoryDialogCreateTitle => 'Add User Memory';

  @override
  String get memoryDialogEditTitle => 'Edit User Memory';

  @override
  String get memoryContentField => 'Memory Content';

  @override
  String get memoryContentRequired => 'Enter the memory content.';

  @override
  String get memoryTagsField => 'Tags';

  @override
  String get memoryTagsHint => 'Type a tag and press Enter to add it';

  @override
  String get memoryTagLimitExceeded => 'A memory can have up to 32 tags.';

  @override
  String get memoryDeleteConfirmTitle => 'Delete User Memory';

  @override
  String get memoryDeleteConfirmBody =>
      'Delete this user memory? This action cannot be undone.';

  @override
  String get memoryTypeUser => 'User Edited';

  @override
  String get memoryEntryCreated => 'User memory created.';

  @override
  String get memoryEntryUpdated => 'User memory updated.';

  @override
  String get memoryEntryDeleted => 'User memory deleted.';

  @override
  String get memoryEnabledLabel => 'Enable Memory';

  @override
  String get memoryEnabledBody =>
      'When disabled, saved user memories stay on disk but are not used at runtime.';

  @override
  String get userMemoryFileLabel => 'Memory Database';

  @override
  String get memoryFileBody =>
      'User memories are stored in OpenHand\'s local SQLite database.';

  @override
  String get memoryFileDefaultPath => 'Database Location';

  @override
  String get memoryOpenDirectory => 'Open Database Folder';

  @override
  String get memoryDisabledTitle => 'Memory is currently disabled';

  @override
  String get memoryDisabledBody =>
      'You can still manage user memories here. To use them at runtime, turn Memory on in Settings > Memory.';

  @override
  String get memoryCreatedAtLabel => 'Created At';

  @override
  String get memoryPersistenceSaveFailedTitle => 'Memory Save Failed';

  @override
  String get memoryPersistenceSaveFailedBody =>
      'Writing the memory database failed. No uncommitted changes were applied. Check database access and disk state.';

  @override
  String get mcpPageTitle => 'MCP';

  @override
  String get mcpPageSubtitle =>
      'Manage local MCP Server configurations with a Cursor-style layout adapted to OpenHand.';

  @override
  String get mcpRefresh => 'Refresh';

  @override
  String get mcpNewServer => 'New Server';

  @override
  String get mcpEmptyTitle => 'No MCP services configured yet';

  @override
  String get mcpEmptyBody =>
      'Add an MCP Server first. OpenHand will save it into ~/.openhand/mcp/mcp_servers.json.';

  @override
  String get mcpLoadFailedTitle => 'Failed to load MCP config';

  @override
  String get mcpOperationFailed => 'The MCP action failed. Please try again.';

  @override
  String get mcpDialogCreateTitle => 'Add MCP Service';

  @override
  String get mcpDialogEditTitle => 'Edit MCP Service';

  @override
  String get mcpNameField => 'Service Name';

  @override
  String get mcpNameRequired => 'Enter a service name.';

  @override
  String get mcpNameDuplicate => 'That service name already exists.';

  @override
  String get mcpTypeField => 'Service Type';

  @override
  String get mcpUrlField => 'Service URL';

  @override
  String get mcpUrlRequired => 'Enter a service URL.';

  @override
  String get mcpUrlInvalid => 'Enter a valid service URL.';

  @override
  String get mcpCommandField => 'Launch Command';

  @override
  String get mcpCommandRequired => 'Enter a launch command.';

  @override
  String get mcpArgsField => 'Command Arguments';

  @override
  String get mcpArgsHint => 'One argument per line';

  @override
  String get mcpServerEnabledLabel => 'Enable this service';

  @override
  String get mcpServerEnabledBody =>
      'When disabled, the service config is kept but the server is not enabled at runtime.';

  @override
  String get mcpServerStatusEnabled => 'Enabled';

  @override
  String get mcpServerStatusDisabled => 'Disabled';

  @override
  String get mcpServerCreated => 'MCP service created.';

  @override
  String get mcpServerUpdated => 'MCP service updated.';

  @override
  String get mcpServerDeleted => 'MCP service deleted.';

  @override
  String get mcpDeleteConfirmTitle => 'Delete MCP Service';

  @override
  String get mcpDeleteConfirmBody => 'Delete this MCP service configuration?';

  @override
  String mcpDeleteAlsoUninstallPackage(String packageName) {
    return 'Also uninstall package ($packageName)';
  }

  @override
  String get mcpDeleteAlsoUninstallPackageBody =>
      'Will uninstall the global package and clean the isolated cache.';

  @override
  String mcpDependencyCleanedUp(String packageName) {
    return '$packageName dependency cleaned up';
  }

  @override
  String mcpDependencyCleanupFailed(String packageName, String error) {
    return '$packageName cleanup failed: $error';
  }

  @override
  String mcpDependencyCleanupError(String packageName, String error) {
    return '$packageName cleanup error: $error';
  }

  @override
  String get mcpTemplateSessionManaged => 'session-managed';

  @override
  String mcpTemplateSessionOn(String status) {
    return 'session on · $status';
  }

  @override
  String mcpTemplateSessionOff(String status) {
    return 'session off · $status';
  }

  @override
  String get mcpTemplateNotRegistered => 'not registered';

  @override
  String mcpTemplateRuntimeEnabledCount(int count) {
    return '$count sessions on';
  }

  @override
  String get mcpDisabledTitle => 'MCP services are currently disabled';

  @override
  String get mcpDisabledBody =>
      'You can still manage service configs here. To enable them at runtime, turn the MCP switch on in Settings > MCP.';

  @override
  String get mcpTransportStreamableHttp => 'Streamable HTTP';

  @override
  String get mcpTransportSse => 'SSE';

  @override
  String get mcpTransportStdio => 'STDIO';

  @override
  String get mcpPersistenceSaveFailedTitle => 'MCP Config Save Failed';

  @override
  String get mcpPersistenceSaveFailedBody =>
      'Writing the MCP config file failed. The UI has been rolled back to the last valid configuration. Check file permissions or disk state.';

  @override
  String get threadsEmptyBody =>
      'No conversation threads yet. Create a new thread to start.';

  @override
  String get threadTemplateDialogTitle => 'Choose a Thread Template';

  @override
  String get threadTemplateDialogBody =>
      'Start a new thread by picking one of the built-in capability templates below.';

  @override
  String get threadCompressionNotice =>
      'Older messages in this thread were compressed into a summary checkpoint to keep the active prompt focused.';

  @override
  String get threadCompressionCheckpointLabel => 'Summary checkpoint';

  @override
  String get aiCompressionThresholdLabel => 'Message Compression Threshold';

  @override
  String get aiCompressionThresholdBody =>
      'When the uncompressed historical messages in the current thread exceed this character threshold, OpenHand will summarize the older slice into a compression checkpoint and keep the most recent slice active.';

  @override
  String get aiCompressionThresholdSave => 'Save Threshold';

  @override
  String get aiCompressionThresholdSaved =>
      'The AI message compression threshold has been updated.';

  @override
  String get aiCompressionThresholdInvalid =>
      'Enter a valid positive integer threshold.';

  @override
  String get aiToolResultCompressionThresholdLabel =>
      'Tool Call Output Compression Threshold';

  @override
  String get aiToolResultCompressionThresholdSave => 'Save Threshold';

  @override
  String get aiToolResultCompressionThresholdSaved =>
      'The tool call output compression threshold has been updated.';

  @override
  String get aiToolResultCompressionThresholdInvalid =>
      'Enter a valid positive integer threshold.';

  @override
  String get aiToolResultCompressionEnabledLabel =>
      'Enable Tool Call Output Compression';

  @override
  String get aiToolResultCompressionEnabledBody =>
      'Controls whether long tool output is summarized when creating compression checkpoints. Normal conversations always deliver complete results to the model; disabling this also keeps raw output in checkpoints and can increase compression cost.';

  @override
  String get aiMicroCompressionEnabledLabel => 'Micro-Compression';

  @override
  String get aiMicroCompressionEnabledBody =>
      'When enabled, older consumed tool results are compacted only inside compression checkpoint prompts, lowering summary cost while keeping live conversation history cache-stable. When disabled, long old results still follow the threshold summary above.';

  @override
  String get aiMessageContentSectionLabel => 'Message Content';

  @override
  String get aiMessageContentFormatLabel => 'Content Format';

  @override
  String get aiMessageContentFormatBody =>
      'Controls how AI assistant messages are rendered. Markdown is the default; PlainText is fastest; HTML uses a third-party renderer with higher token cost and falls back per the rule below on render failure.';

  @override
  String get aiMessageContentFormatMarkdown => 'Markdown';

  @override
  String get aiMessageContentFormatPlainText => 'PlainText';

  @override
  String get aiMessageContentFormatHtml => 'HTML';

  @override
  String get aiMessageContentFormatHtmlTokenWarning =>
      'HTML mode injects extra format constraints into every prompt; token cost is slightly higher.';

  @override
  String get aiHtmlRenderFallbackLabel => 'HTML Render Fallback';

  @override
  String get aiHtmlRenderFallbackBody =>
      'Strategy used when HTML parsing or rendering fails. Markdown re-parses as Markdown; PlainText shows the raw text directly.';

  @override
  String get aiHtmlRenderFallbackMarkdown => 'Markdown';

  @override
  String get aiHtmlRenderFallbackPlainText => 'PlainText';

  @override
  String get aiHtmlContentRichnessLabel => 'HTML Content Richness';

  @override
  String get aiHtmlContentRichnessBody =>
      'Controls the visual intensity injected into the model under HTML mode. Balanced is the default (restrained grayscale); Rich unlocks color and cards; Vivid pushes gradients, glassmorphism, and hero blocks to the max — highest token cost.';

  @override
  String get aiHtmlContentRichnessBalanced => 'Balanced';

  @override
  String get aiHtmlContentRichnessRich => 'Rich';

  @override
  String get aiHtmlContentRichnessVivid => 'Vivid';

  @override
  String get aiToolResultCompressionHeadTailWindowLabel =>
      'Compression Head/Tail Window';

  @override
  String get aiToolResultCompressionHeadTailWindowBody =>
      'How many head/tail characters of the raw output to retain in the condensed summary. Default 256; 0 disables head/tail snippets; range 0–8192.';

  @override
  String get aiToolResultCompressionHeadTailWindowSave => 'Save Window';

  @override
  String get aiToolResultCompressionHeadTailWindowSaved =>
      'Head/tail window updated.';

  @override
  String get aiToolResultCompressionHeadTailWindowInvalid =>
      'Enter an integer between 0 and 8192.';

  @override
  String get aiToolResultCompressionMaxPathHitsLabel =>
      'Compression Path Extraction Cap';

  @override
  String get aiToolResultCompressionMaxPathHitsBody =>
      'Maximum number of affected file paths extracted into the summary. Default 12; 0 disables extraction; range 0–200.';

  @override
  String get aiToolResultCompressionMaxPathHitsSave => 'Save Cap';

  @override
  String get aiToolResultCompressionMaxPathHitsSaved =>
      'Path extraction cap updated.';

  @override
  String get aiToolResultCompressionMaxPathHitsInvalid =>
      'Enter an integer between 0 and 200.';

  @override
  String get aiWriteToolSummaryMaxCharsLabel => 'Write Tool Summary Char Cap';

  @override
  String get aiWriteToolSummaryMaxCharsBody =>
      'Maximum characters of result_text retained in write-style tool summaries (write/edit/multiedit/notebookedit/write-like bash). Default 280; 0 omits the summary; range 0–8192.';

  @override
  String get aiWriteToolSummaryMaxCharsSave => 'Save Cap';

  @override
  String get aiWriteToolSummaryMaxCharsSaved =>
      'Write tool summary char cap updated.';

  @override
  String get aiWriteToolSummaryMaxCharsInvalid =>
      'Enter an integer between 0 and 8192.';

  @override
  String get aiMaxRecentErrorsLabel => 'Session Recent Errors Retention';

  @override
  String get aiMaxRecentErrorsBody =>
      'Number of recent error records retained in AI session state. Default 20; range 0-1000.';

  @override
  String get aiMaxRecentErrorsSave => 'Save Limit';

  @override
  String get aiMaxRecentErrorsSaved =>
      'Session recent errors retention updated.';

  @override
  String get aiMaxRecentErrorsInvalid => 'Enter an integer between 0 and 1000.';

  @override
  String get aiMaxPlanHistoryEntriesLabel => 'Plan History Retention';

  @override
  String get aiMaxPlanHistoryEntriesBody =>
      'Max entries kept in plan_history under Plan mode. Default 20; range 0-1000.';

  @override
  String get aiMaxPlanHistoryEntriesSave => 'Save Limit';

  @override
  String get aiMaxPlanHistoryEntriesSaved => 'Plan history retention updated.';

  @override
  String get aiMaxPlanHistoryEntriesInvalid =>
      'Enter an integer between 0 and 1000.';

  @override
  String get aiMaxTruncationContinuationsLabel => 'Auto-Continuation Limit';

  @override
  String get aiMaxTruncationContinuationsBody =>
      'Max consecutive auto-continuations after the model output is truncated (finish_reason=length). Default 5; range 0-100.';

  @override
  String get aiMaxTruncationContinuationsSave => 'Save Limit';

  @override
  String get aiMaxTruncationContinuationsSaved =>
      'Auto-continuation limit updated.';

  @override
  String get aiMaxTruncationContinuationsInvalid =>
      'Enter an integer between 0 and 100.';

  @override
  String get aiEstimatedCharactersPerTokenLabel =>
      'Token Char Estimation Ratio';

  @override
  String get aiEstimatedCharactersPerTokenBody =>
      'Approximate characters per token, used for context budget estimation. Default 4; range 1-32.';

  @override
  String get aiEstimatedCharactersPerTokenSave => 'Save Ratio';

  @override
  String get aiEstimatedCharactersPerTokenSaved =>
      'Token char estimation ratio updated.';

  @override
  String get aiEstimatedCharactersPerTokenInvalid =>
      'Enter an integer between 1 and 32.';

  @override
  String get aiImageSizeLimitBody =>
      'When the user attaches an image larger than this cap, OpenHand automatically compresses it (quality + resolution) before sending. Accepts decimal MB values; range 0.0625 MB (64 KB) to 64 MB.';

  @override
  String get aiImageSizeLimitFieldLabel => 'Limit (MB)';

  @override
  String get aiImageSizeLimitSave => 'Save Limit';

  @override
  String get aiImageSizeLimitSaved =>
      'The image attachment size limit has been updated.';

  @override
  String get aiImageSizeLimitInvalid => 'Enter a valid positive number of MB.';

  @override
  String get imageEditorAspectFree => 'Free';

  @override
  String get imageEditorAspectOriginal => 'Original';

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
  String get imageEditorAspectCircle => 'Circle';

  @override
  String get imageEditorFlipHorizontal => 'Flip Horizontal';

  @override
  String get imageEditorFlipVertical => 'Flip Vertical';

  @override
  String get imageEditorSaturationLabel => 'Saturation';

  @override
  String get imageEditorExposureLabel => 'Exposure';

  @override
  String get imageEditorHueLabel => 'Hue';

  @override
  String get imageEditorVignetteLabel => 'Vignette';

  @override
  String get imageEditorFineRotationLabel => 'Fine Rotation (°)';

  @override
  String get imageEditorSaveToFile => 'Save To File';

  @override
  String get imageEditorCopyToClipboard => 'Copy To Clipboard';

  @override
  String imageEditorSavedTo(String path) {
    return 'Saved: $path';
  }

  @override
  String imageEditorSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get imageEditorClipboardCopiedBitmap =>
      'Image copied to the clipboard. The file path was also copied as text.';

  @override
  String imageEditorClipboardCopiedPath(String path) {
    return 'Image file path copied to the clipboard: $path';
  }

  @override
  String get imageEditorApplyButton => 'Apply';

  @override
  String get imageEditorUndoButton => 'Undo';

  @override
  String get imageEditorResetAllButton => 'Reset All';

  @override
  String get imageEditorCompareHold => 'Hold To Compare';

  @override
  String get imageEditorCompareRelease => 'Release';

  @override
  String get imageEditorCompareOriginal => 'Original';

  @override
  String get imageEditorWatermarkColorLabel => 'Text Color';

  @override
  String get imageEditorWatermarkColorHue => 'Hue';

  @override
  String get imageEditorWatermarkColorSaturation => 'Saturation';

  @override
  String get imageEditorWatermarkColorLightness => 'Lightness';

  @override
  String get imageEditorApplySuccess => 'Adjustments applied';

  @override
  String get imageEditorProcessing => 'Processing...';

  @override
  String get builtinToolTimeoutLabel => 'Timeout (seconds)';

  @override
  String builtinToolTimeoutHint(int seconds) {
    return 'Default ${seconds}s';
  }

  @override
  String builtinToolTimeoutHelper(int seconds) {
    return 'Blank = default ${seconds}s. Runtime guard for side-effect-free tools; Task/Bash/write tools use their own limits.';
  }

  @override
  String get builtinToolRetryLabel => 'Retry on failure / timeout';

  @override
  String get builtinToolRetryBody =>
      'Off by default. Only retries side-effect-free tools on real failed/timed_out outcomes; never retries invalid arguments, denied calls, Task, write commands, file edits, background processes, skill changes, or memory writes.';

  @override
  String builtinToolMaxRetriesLabel(int max) {
    return 'Max Retries (0–$max)';
  }

  @override
  String builtinToolMaxRetriesHelper(int max) {
    return 'Excluding first attempt; capped at $max';
  }

  @override
  String get builtinToolBackoffLabel => 'Retry backoff base (ms)';

  @override
  String builtinToolBackoffHint(int ms) {
    return 'Default ${ms}ms';
  }

  @override
  String builtinToolBackoffHelper(int max) {
    return 'Exponential: nth retry waits base × 2^(N-1) ms, capped at ${max}ms';
  }

  @override
  String selfLearningFlushIntervalLabel(int ms) {
    return 'Stream flush interval: ${ms}ms';
  }

  @override
  String selfLearningFlushIntervalHelper(int min, int max) {
    return 'Persistence interval for self-learning card streaming output ($min–${max}ms). Smaller=more real-time but more layout jitter; larger=smoother but higher per-chunk latency. Defaults to 600ms.';
  }

  @override
  String get tsmRenameThreadTitle => 'Rename Thread';

  @override
  String get tsmRenameHint => 'Enter a thread title';

  @override
  String get tsmRenameFailed => 'Rename failed';

  @override
  String get tsmDeleteThreadTitle => 'Delete Thread';

  @override
  String get tsmDeleteSelectedTitle => 'Delete Selected Threads';

  @override
  String tsmDeleteSelectedConfirm(int count) {
    return 'Will permanently delete $count threads and their messages. This cannot be undone.';
  }

  @override
  String tsmDeleteFailedCount(int count) {
    return '$count thread(s) failed to delete';
  }

  @override
  String get tsmSessionMissing => 'Session is missing or deleted';

  @override
  String get tsmExportSessionDataTitle => 'Export Session Data';

  @override
  String tsmExportingSession(String title) {
    return 'Exporting \"$title\"…';
  }

  @override
  String get tsmExportComplete => 'Export complete';

  @override
  String get tsmExportFailed => 'Export failed';

  @override
  String get tsmChooseExportFolder => 'Choose Export Folder';

  @override
  String get tsmBatchExportTitle => 'Batch Export';

  @override
  String tsmBatchExportSubtitle(int count) {
    return 'About to export $count threads…';
  }

  @override
  String tsmBatchExportDone(int ok, int failed) {
    return 'Batch export done: $ok ok / $failed failed';
  }

  @override
  String get tsmMenuPreview => 'Preview';

  @override
  String get tsmMenuRename => 'Rename';

  @override
  String get tsmMenuExportSession => 'Export Session';

  @override
  String get tsmMenuPin => 'Pin';

  @override
  String get tsmMenuUnpin => 'Unpin';

  @override
  String get tsmMenuArchive => 'Archive';

  @override
  String get tsmMenuUnarchive => 'Unarchive';

  @override
  String get tsmMenuDelete => 'Delete';

  @override
  String get tsmPinUpdateFailed => 'Failed to update pin state';

  @override
  String get tsmArchiveUpdateFailed => 'Failed to update archive state';

  @override
  String get tsmUntitledThread => '(Untitled Thread)';

  @override
  String tsmPreviewMessageCount(int count) {
    return '$count messages';
  }

  @override
  String get tsmClosePreview => 'Close Preview';

  @override
  String get tsmNoMessages => 'No messages';

  @override
  String get tsmEmptyMessage => '(empty)';

  @override
  String get tsmSearchHint => 'Search by title or ID';

  @override
  String get tsmDensityComfortable => 'Comfortable';

  @override
  String get tsmDensityCompact => 'Compact';

  @override
  String get tsmAllTemplates => 'All Templates';

  @override
  String tsmSortDisabledHint(String mode) {
    return 'Sorted by \"$mode\". Drag handles are disabled; switch back to \"Manual Order\" to reorder.';
  }

  @override
  String get tsmSortManual => 'Manual Order';

  @override
  String get tsmSortUpdated => 'Recently Updated';

  @override
  String get tsmSortCreated => 'Recently Created';

  @override
  String get tsmSortSize => 'By Size';

  @override
  String get tsmSortMessages => 'By Messages';

  @override
  String get tsmSortToken => 'By Token';

  @override
  String get tsmHideArchived => 'Hide Archived';

  @override
  String get tsmShowArchived => 'Show Archived';

  @override
  String get tsmExitSelection => 'Exit Selection';

  @override
  String get tsmEnterSelection => 'Multi-select';

  @override
  String get tsmClose => 'Close';

  @override
  String get tsmTitle => 'Thread Session Management';

  @override
  String tsmHeaderSubtitle(int count) {
    return '$count thread(s) · long-press / drag the handle to reorder, double-click / right-click for more';
  }

  @override
  String tsmSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get tsmBatchExportButton => 'Batch Export';

  @override
  String get tsmDeleteSelectedButton => 'Delete Selected';

  @override
  String get tsmEmptyState => 'No thread sessions yet';

  @override
  String get tsmCancel => 'Cancel';

  @override
  String get settingsThreadSessionManagementTitle =>
      'Thread Session Management';

  @override
  String get settingsThreadSessionManagementSubtitle =>
      'Inspect every thread\'s title, created/updated time, storage footprint, message breakdown, and token stats. Supports drag-reorder, multi-select delete, and a double-click / right-click menu for rename/export/delete. The dialog enter/exit animation follows the global dialog animation settings.';

  @override
  String get settingsThreadSessionManagementOpen => 'Open Manager';

  @override
  String get settingsMessageGatewayTitle => 'Message Gateway';

  @override
  String get settingsMessageGatewayDescription =>
      'Configure the built-in Web General Message Platform, including listener, auth, sessions, web chat, health checks, logs, and operations.';

  @override
  String get tsmRowUnknown => 'unknown';

  @override
  String get tsmRowCreated => 'Created';

  @override
  String get tsmRowUpdated => 'Updated';

  @override
  String get tsmRowSize => 'Size';

  @override
  String get tsmRowMessages => 'Messages';

  @override
  String get tsmRowToken => 'Token';

  @override
  String get tsmRowByKind => 'By kind';

  @override
  String get inputRepairTitle => 'Input Repair';

  @override
  String get inputRepairBody =>
      'Reclaim leftover child processes (osascript, LSP, MCP, …) and reset the macOS input-method context — fixes global TextField failing to accept input, copy/paste, or ESC dismiss.';

  @override
  String get inputRepairButton => 'Repair Input';

  @override
  String get inputRepairDone => 'Input context reset.';

  @override
  String inputRepairDoneDetail(int count) {
    return 'Input context reset; reclaimed $count background child processes.';
  }

  @override
  String get proxySectionTitle => 'System';

  @override
  String get proxySectionBody =>
      'Every internal HTTP client (WebSearch / WebFetch, etc.) routes through the proxy chosen here. Changes apply immediately, no restart required.';

  @override
  String get proxyModeLabel => 'Proxy mode';

  @override
  String get proxyModeBody =>
      'Controls how OpenHand internal HTTP clients (WebSearch / WebFetch, etc.) choose a proxy.';

  @override
  String get proxyModeDisabled => 'No proxy';

  @override
  String get proxyModeAutomatic => 'Auto-detect (default)';

  @override
  String get proxyModeManual => 'Manual';

  @override
  String get proxyProtocolsLabel => 'Protocols';

  @override
  String get proxyProtocolsBody =>
      'Multi-select. At least one must remain; clearing all restores HTTP + HTTPS.';

  @override
  String get proxyHostLabel => 'Server (IP or hostname)';

  @override
  String get proxyPortLabel => 'Port';

  @override
  String get proxyAuthLabel => 'Enable proxy authentication';

  @override
  String get proxyAuthBody =>
      'Username / password are only used when this is on (HTTP Basic).';

  @override
  String get proxyUsernameLabel => 'Username';

  @override
  String get proxyPasswordLabel => 'Password';

  @override
  String get proxyExceptionsLabel => 'Bypass proxy for these hosts and domains';

  @override
  String get proxyExceptionsBody =>
      'One entry per line. Supports IP (127.0.0.1), IPv4 CIDR (192.168.0.0/16), domain (example.com matches subdomains), glob (*.example.com), and regex (/^api\\d+\\.example\\.com\$/i). localhost / 127.0.0.1 / ::1 are always direct.';

  @override
  String get proxyExceptionsHint =>
      'e.g.\n*.local\n10.0.0.0/8\n/^api\\d+\\.example\\.com\$/i';

  @override
  String get proxyTestButton => 'Test proxy connectivity';

  @override
  String get proxyTesting => 'Testing…';

  @override
  String proxyTestSuccess(int latency, String via) {
    return 'OK ($latency ms, via $via)';
  }

  @override
  String proxyTestFailure(String reason) {
    return 'Failed: $reason';
  }

  @override
  String get proxyTestEndpointLabel => 'Test URL';

  @override
  String get proxyTestEndpointHint =>
      'Default: https://www.google.com/generate_204';

  @override
  String get proxyTestVerdictDirect => 'direct';

  @override
  String proxyTestVerdictProxy(String endpoint) {
    return 'proxy $endpoint';
  }

  @override
  String get proxyTestEndpointInvalid =>
      'Test URL is invalid (must start with http:// or https://)';

  @override
  String get proxyTestConsoleTitle => 'Proxy Connectivity Diagnostic';

  @override
  String get proxyTestConsoleRunning => 'Probing route…';

  @override
  String get proxyTestConsoleSucceeded => 'Done: route healthy';

  @override
  String get proxyTestConsoleFailed => 'Done: issues detected';

  @override
  String get proxyTestConsoleCopy => 'Copy log';

  @override
  String get proxyTestConsoleCopied => 'Log copied to clipboard';

  @override
  String get proxyTestConsoleClose => 'Close';

  @override
  String get proxyTestConsoleRerun => 'Rerun';

  @override
  String get proxyTestConsoleMaximize => 'Maximize';

  @override
  String get proxyTestConsoleRestore => 'Restore';

  @override
  String get proxyTestConsoleClear => 'Clear console';

  @override
  String get tokenPopupCostHeading => 'Cost';

  @override
  String get tokenPopupCostInput => 'Input';

  @override
  String get tokenPopupCostOutput => 'Output';

  @override
  String get tokenPopupCostCacheRead => 'Cache read';

  @override
  String get tokenPopupCostCacheWrite => 'Cache write';

  @override
  String get tokenPopupCostTotal => 'Total';

  @override
  String get tokenDialUnit => 'Token';

  @override
  String get tokenPopupInputHeading => 'Input';

  @override
  String get tokenPopupPrompt => 'Prompt';

  @override
  String get tokenPopupAudioInput => 'Audio input';

  @override
  String get tokenPopupImageInput => 'Image input';

  @override
  String get tokenPopupVideoInput => 'Video input';

  @override
  String get tokenPopupCacheRead => 'Cache Read';

  @override
  String get tokenPopupCacheWrite => 'Cache Write';

  @override
  String get tokenPopupOutputHeading => 'Output';

  @override
  String get tokenPopupCompletion => 'Completion';

  @override
  String get tokenPopupReasoning => 'Reasoning';

  @override
  String get tokenPopupWebSearchHeading => 'Web search';

  @override
  String get tokenPopupWebSearchCalls => 'Tool calls';

  @override
  String get tokenPopupWebSearchPages => 'Pages';

  @override
  String get tokenPopupGrandTotal => 'Total';

  @override
  String get tokenPopupContextOverview => 'Context overview';

  @override
  String get tokenPopupContextMeasured =>
      'Measured total · apportioned categories';

  @override
  String get tokenPopupContextEstimated => 'Estimated from request content';

  @override
  String get tokenPopupContextEmpty =>
      'Send the next message to generate this overview';

  @override
  String get tokenPopupContextSystemPrompt => 'System prompt';

  @override
  String get tokenPopupContextBuiltinTools => 'Built-in tools';

  @override
  String get tokenPopupContextMcp => 'MCP';

  @override
  String get tokenPopupContextInstructions => 'Instructions';

  @override
  String get tokenPopupContextMemory => 'Memory';

  @override
  String get tokenPopupContextSkills => 'Skills';

  @override
  String get tokenPopupContextHooks => 'Hooks';

  @override
  String get tokenPopupContextConversation => 'Conversation';

  @override
  String get tokenPopupContextRuntime => 'Runtime';

  @override
  String get tokenPopupContextWindow => 'Context window';

  @override
  String get tokenPopupCompactNow => 'Compact now';

  @override
  String get tokenPopupCompacting => 'Compacting…';

  @override
  String get tokenPopupSessionHeading => 'Session';

  @override
  String get tokenPopupMessages => 'Messages';

  @override
  String get tokenPopupPromptBuilds => 'Prompt Builds';

  @override
  String get tokenPopupPromptChars => 'Prompt Chars';

  @override
  String get tokenPopupCacheHitModeExcludeExpired => 'Exclude expiry anomalies';

  @override
  String get tokenPopupCacheHitModeIncludeExpired => 'Include expiry anomalies';

  @override
  String tokenPopupExcludedRounds(int count) {
    return '$count excluded';
  }

  @override
  String get tokenPopupPrefixReuse => 'Prefix reuse';

  @override
  String tokenPopupTooltipFreshReuse(String fresh, int reuse) {
    return '+$fresh new · reuse $reuse%';
  }

  @override
  String get tokenPopupFirstRequestShort => 'Ignored';

  @override
  String get tokenPopupFirstRequestNotAveraged => 'Not averaged';

  @override
  String get tokenPopupTrendNoData =>
      'No cache hit data yet. The trend appears after messages are sent.';

  @override
  String get tokenPopupTrendOnlyFirstIgnored =>
      'The first request is ignored. The trend starts after the next normal request.';

  @override
  String get tokenPopupTrendFirstReferenceOnly =>
      'The first request is reference only and is not averaged.';

  @override
  String get tokenPopupUncached => 'Uncached';

  @override
  String get toolbarSessionMetadata => 'Session Metadata';

  @override
  String get toolbarShowPlan => 'Show Plan';

  @override
  String get toolbarHidePlan => 'Hide Plan';

  @override
  String get toolbarPlanAwaitingApproval => 'Plan Awaiting Approval';

  @override
  String get toolbarPlanNeedsReview => 'Plan Needs Review';

  @override
  String get toolbarPlanNeedsAttention => 'Plan Needs Attention';

  @override
  String get toolbarPlanCompleted => 'Plan Completed';

  @override
  String get toolbarPlanInProgress => 'Plan In Progress';

  @override
  String get toolbarPlanConfirmToBegin => 'Confirm to begin execution';

  @override
  String get toolbarPlanInspectBeforeResume =>
      'Inspect completed steps, artifacts, and todos before resuming';

  @override
  String get toolbarPlanStepFailed => 'A step failed. Review it and continue.';

  @override
  String get toolbarPlanPending => 'Pending';

  @override
  String get toolbarPlanReview => 'Review';

  @override
  String get toolbarToolsProtocolUnsupported =>
      'The current model protocol does not support tool calls';

  @override
  String get toolbarRuntimeNoSnapshot => 'No runtime tool snapshot yet';

  @override
  String get toolbarToolsCatalogStale =>
      'The tool catalog is stale and will refresh next round';

  @override
  String get toolbarRuntimeCatalogSynced =>
      'The runtime tool catalog is synchronized';

  @override
  String get toolbarPlanAwaitingNoExecTools =>
      'The plan is awaiting approval, so execution tools stay hidden';

  @override
  String get toolbarPlanReviewBeforeResume =>
      'Review completed steps, artifacts, and todos before resuming';

  @override
  String get toolbarPlanApprovedExecOpen =>
      'The plan is approved and execution tools are available';

  @override
  String get toolbarPlanOnlyPlanningExitAllowed =>
      'Only planning tools are available until the execution plan is ready';

  @override
  String get toolbarPlanOnlyPlanningOnly =>
      'Only planning tools are available right now';

  @override
  String get toolbarModeJustSwitched =>
      'The mode just changed, so the tool catalog will refresh next round';

  @override
  String get toolbarChatModeNoTools =>
      'No tools are available in chat mode right now';

  @override
  String get toolbarChatModeAllTools =>
      'Chat mode currently exposes the full runtime catalog';

  @override
  String get toolbarRuntimeNoSnapshotPrompt =>
      'No runtime snapshot is available yet; send a request first';

  @override
  String get toolbarGateNoReason => 'No gate reason available';

  @override
  String get toolbarGateProtocolUnsupportedSwitchPlan =>
      'The current model protocol does not support tool calls. Click to switch to plan mode.';

  @override
  String get toolbarGateChatActiveSwitchPlan =>
      'Chat mode is active. Click to switch to plan mode.';

  @override
  String get toolbarGatePlanActiveSwitchChat =>
      'Plan mode is active. Click to switch to chat mode.';

  @override
  String get toolbarGateProtocolUnsupportedSwitchChat =>
      'The current model protocol does not support tool calls. Plan mode can still organize steps, but tool execution stays unavailable. Click to switch to chat mode.';

  @override
  String get toolbarGatePlanJustSwitchedToChat =>
      'Plan mode just changed. Runtime tools will refresh on the next round. Click to switch to chat mode.';

  @override
  String get toolbarGatePlanAwaitingSwitchChat =>
      'The plan is awaiting approval. Execution tools stay hidden until approval. Click to switch to chat mode.';

  @override
  String get toolbarGatePlanReviewSwitchChat =>
      'The plan needs review. Inspect completed steps, artifacts, and todos before continuing. Click to switch to chat mode.';

  @override
  String get toolbarGatePlanExecutingSwitchChat =>
      'The plan is executing. Runtime tools are exposed according to the current catalog. Click to switch to chat mode.';

  @override
  String get toolbarGatePlanModeSwitchChat =>
      'Plan mode is active. It plans first, then executes after approval. Click to switch to chat mode.';

  @override
  String get toolbarFilesShow => 'Project Files';

  @override
  String get toolbarFilesHide => 'Hide Files';

  @override
  String get toolbarRuntimeModeChat => 'Chat Mode';

  @override
  String get toolbarRuntimeModeChatCompact => 'Chat Mode';

  @override
  String get toolbarRuntimeModePlan => 'Plan Mode';

  @override
  String get toolbarRuntimeModePlanCompact => 'Plan Mode';

  @override
  String get toolbarRuntimeModePlanAwaiting => 'Plan Awaiting Approval';

  @override
  String get toolbarRuntimeModePlanAwaitingCompact => 'Plan Awaiting';

  @override
  String get toolbarRuntimeModePlanReview => 'Plan Needs Review';

  @override
  String get toolbarRuntimeModePlanReviewCompact => 'Plan Review';

  @override
  String get toolbarRuntimeModePlanExecution => 'Plan Execution';

  @override
  String get toolbarRuntimeModePlanExecutionCompact => 'Plan Execute';

  @override
  String get toolbarRuntimeModePlanDrafting => 'Plan Drafting';

  @override
  String get toolbarRuntimeModePlanDraftCompact => 'Plan Draft';

  @override
  String toolbarRuntimeNotices(int count) {
    return '$count runtime notices';
  }

  @override
  String toolbarMcpLazyLoading(int loaded, int total) {
    return 'MCP $loaded/$total loaded';
  }

  @override
  String snackToolSearchLoaded(int loaded, int total) {
    return 'ToolSearch loaded $loaded/$total MCP tool(s)';
  }

  @override
  String get snackToolSearchLoadedAction => 'View list';

  @override
  String get snackToolSearchLoadedDialogTitle =>
      'MCP tools loaded by ToolSearch';

  @override
  String get snackToolSearchLoadedDialogClose => 'Close';

  @override
  String get snackToolSearchLoadedCopyAction => 'Copy select:';

  @override
  String get snackToolSearchLoadedCopiedToast => 'Copied';

  @override
  String get snackToolSearchLoadedClearAction => 'Clear loaded list';

  @override
  String get snackToolSearchLoadedClearedToast => 'Loaded list cleared';

  @override
  String get snackToolSearchLoadedGroupOther => 'Other (no server prefix)';

  @override
  String get snackToolSearchLoadedCopyGroupAction => 'Copy entire group';

  @override
  String get snackToolSearchLoadedTabLoaded => 'Loaded';

  @override
  String get snackToolSearchLoadedTabHistory => 'Load history';

  @override
  String get snackToolSearchLoadedHistoryEmpty =>
      'No ToolSearch loads in this session yet';

  @override
  String get snackToolSearchLoadedHistoryQueryPrefix => 'Query: ';

  @override
  String get snackToolSearchLoadedFilterHint => 'Filter by name…';

  @override
  String get snackToolSearchLoadedHistoryFilterHint =>
      'Filter by name or query…';

  @override
  String get snackToolSearchLoadedSourceAi => 'AI session';

  @override
  String get snackToolSearchLoadedSourceHarness => 'Harness phase';

  @override
  String get snackToolSearchLoadedReplayedToast =>
      'Re-issued ToolSearch with previous selection';

  @override
  String get snackToolSearchLoadedReplayPendingToast =>
      'About to dispatch — tap Cancel to abort';

  @override
  String get snackToolSearchLoadedReplayCancelAction => 'Cancel';

  @override
  String get snackToolSearchLoadedReplayCancelledToast =>
      'Dispatch cancelled — composer cleared';

  @override
  String get snackToolSearchLoadedSourceFilterAll => 'All';

  @override
  String get snackToolSearchLoadedSourceFilterAi => 'AI only';

  @override
  String get snackToolSearchLoadedSourceFilterHarness => 'Harness only';

  @override
  String snackToolSearchLoadedSummary(int queries, int tools) {
    return 'Loaded $tools MCP tool(s) from $queries query(ies) in this session';
  }

  @override
  String get snackToolSearchLoadedHistoryReplayAction =>
      'Copy this batch as select:…';

  @override
  String get snackToolSearchLoadedHistoryClearAction => 'Clear history';

  @override
  String get snackToolSearchLoadedHistoryExportTooltip => 'Export history';

  @override
  String get snackToolSearchLoadedHistoryExportCsv => 'Copy as CSV';

  @override
  String get snackToolSearchLoadedHistoryExportMarkdown => 'Copy as Markdown';

  @override
  String get snackToolSearchLoadedHistoryExportJson => 'Copy as JSON';

  @override
  String get snackToolSearchLoadedHistoryExportSaveCsv => 'Save as CSV…';

  @override
  String get snackToolSearchLoadedHistoryExportSaveMarkdown =>
      'Save as Markdown…';

  @override
  String get snackToolSearchLoadedHistoryExportSaveJson => 'Save as JSON…';

  @override
  String get snackToolSearchLoadedHistoryExportCsvHint =>
      'Spreadsheet-friendly; one row per query.';

  @override
  String get snackToolSearchLoadedHistoryExportMarkdownHint =>
      'GitHub-flavored table; great for issues / docs.';

  @override
  String get snackToolSearchLoadedHistoryExportJsonHint =>
      'Structured payload; can be imported back into OpenHand.';

  @override
  String get toolSearchLoadedHistoryImportTooltip => 'Import a JSON dump';

  @override
  String get toolSearchLoadedHistoryImportDialogTitle =>
      'Imported ToolSearch history';

  @override
  String toolSearchLoadedHistoryImportDialogCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
      zero: 'no entries',
    );
    return '$_temp0';
  }

  @override
  String get toolSearchLoadedHistoryImportDialogEmpty =>
      'No entries found in the file.';

  @override
  String get toolSearchLoadedHistoryImportDialogClose => 'Close';

  @override
  String snackToolSearchLoadedHistoryExportSavedToast(int count, String path) {
    return 'Saved $count entries to $path';
  }

  @override
  String snackToolSearchLoadedHistoryExportSaveFailedToast(String error) {
    return 'Failed to save: $error';
  }

  @override
  String get snackToolSearchLoadedHistoryExportRevealAction => 'Reveal';

  @override
  String get snackToolSearchLoadedHistoryExportEmptyToast =>
      'History is empty (after filter); nothing to export.';

  @override
  String snackToolSearchLoadedHistoryExportedToast(int count) {
    return 'Copied $count history entries to clipboard.';
  }

  @override
  String get snackToolSearchLoadedHistoryClearedToast => 'Load history cleared';

  @override
  String get mcpLazyLoadingViewLoadedAction =>
      'View loaded list (current session)';

  @override
  String get mcpToolSearchExportLastDirResetAction =>
      'Reset remembered export folder';

  @override
  String get mcpToolSearchExportLastDirResetToast =>
      'Tool search export folder cleared';

  @override
  String get mcpLazyLoadingNoActiveSession => 'No active session right now';

  @override
  String toolbarPlanStepsCompleted(int completed, int total) {
    return '$completed/$total steps completed';
  }

  @override
  String get mdlEdEnterAValidBaseUrlFirst => 'Enter a valid Base URL first';

  @override
  String get mdlEdNoModelsFoundFromThisProvider =>
      'No models found from this provider.';

  @override
  String get mdlEdProviderName => 'Provider Name';

  @override
  String get mdlEdOptionalEGDeepseekLocalOllama =>
      'Optional, e.g. DeepSeek, Local Ollama';

  @override
  String get mdlEdCurrentlyActiveModel => 'Currently active model';

  @override
  String get mdlEdClickToSetAsActiveModel => 'Click to set as active model';

  @override
  String get mdlEdTapScanModelsToDiscoverModels =>
      'Tap \"Scan Models\" to discover models automatically, or add manually below.';

  @override
  String get mdlEdActiveModelId => 'Active Model ID';

  @override
  String get mdlEdTheModelUsedForConversationsSelect =>
      'The model used for conversations. Select from the list above or type directly.';

  @override
  String get mdlEdMaxContextTokens => 'Max Context Tokens';

  @override
  String get mdlEdOptionalLimitsTheHistorySliceUsed =>
      'Optional. Limits the history slice used during compression.';

  @override
  String get mdlEdEnterAWholeNumberGreaterThan =>
      'Enter a whole number greater than 0';

  @override
  String get mdlEdRequestMethod => 'Request Method';

  @override
  String get mdlEdOutputMode => 'Output Mode';

  @override
  String get mdlEdStreaming => 'Streaming';

  @override
  String get mdlEdNonStreaming => 'Non-streaming';

  @override
  String get mdlEdMaxOutputTokens => 'Max Output Tokens';

  @override
  String get mdlEdOptionalUsesAdapterDefaultIfUnset =>
      'Optional. Uses adapter default if unset.';

  @override
  String get mdlEdTemperature => 'Temperature';

  @override
  String get mdlEd0020Default0 => '0.0 ~ 2.0, default 0.7';

  @override
  String get mdlEdEnterANumberBetween00 => 'Enter a number between 0.0 and 2.0';

  @override
  String get mdlEdCustomHeaders => 'Custom Headers';

  @override
  String get mdlEdAdd => 'Add';

  @override
  String get mdlEdNoCustomHeadersTapAddTo =>
      'No custom headers. Tap \"Add\" to create one.';

  @override
  String get mdlEdHeaderName => 'Header Name';

  @override
  String get mdlEdHeaderValue => 'Header Value';

  @override
  String get mdlEdEditModelProfile => 'Edit Model Profile';

  @override
  String get mdlEdDisplayName => 'Display Name';

  @override
  String get mdlEdOptionalShownInTheUi => 'Optional, shown in the UI';

  @override
  String get mdlEdDescription => 'Description';

  @override
  String get mdlEdMultimodalSupport => 'Multimodal Support';

  @override
  String get mdlEdAutoDetect => 'Auto-detect';

  @override
  String get mdlEdYes => 'Yes';

  @override
  String get mdlEdNo => 'No';

  @override
  String get mdlEdSupportsAttachments => 'Supports Attachments';

  @override
  String get mdlEdReasoningEcho => 'Include Reasoning History';

  @override
  String get mdlEdReasoningEchoHint =>
      'Controls whether prior thinking/reasoning content is echoed back into future prompt history for this model.';

  @override
  String get mdlEdSupportedModalities => 'Supported Modalities';

  @override
  String get mdlEdText => 'Text';

  @override
  String get mdlEdImage => 'Image';

  @override
  String get mdlEdVideo => 'Video';

  @override
  String get mdlEdAudio => 'Audio';

  @override
  String get mdlEdGenerationCapabilities => 'Generation Capabilities';

  @override
  String get mdlEdPdf => 'PDF';

  @override
  String get mdlEdPpt => 'PPT';

  @override
  String get mdlEdTokenLimits => 'Token Limits';

  @override
  String get mdlEdContextLength => 'Context Length';

  @override
  String get mdlEdSummaryLength => 'Summary Length';

  @override
  String get mdlEdOutputLength => 'Output Length';

  @override
  String get mdlEdThinkingLength => 'Thinking Length';

  @override
  String get mdlEdTokenPricingUsd1mTokensLeave =>
      'Token pricing (USD / 1M tokens, leave blank if unset)';

  @override
  String get mdlEdInput => 'Input';

  @override
  String get mdlEdOutput => 'Output';

  @override
  String get mdlEdCacheRead => 'Cache Read';

  @override
  String get mdlEdCacheWrite => 'Cache Write';

  @override
  String get mdlEdOpenRouterMetadataOverrides =>
      'OpenRouter Metadata Overrides';

  @override
  String get mdlEdCanonicalSlug => 'Canonical model slug (canonical_slug)';

  @override
  String get mdlEdHuggingFaceId => 'Hugging Face model ID (hugging_face_id)';

  @override
  String get mdlEdKnowledgeCutoff => 'Knowledge cutoff (knowledge_cutoff)';

  @override
  String get mdlEdExpirationDate => 'Expiration date (expiration_date)';

  @override
  String get mdlEdSupportedParametersCsv => 'Supported parameters (CSV)';

  @override
  String get mdlEdSupportedParametersCsvHint =>
      'For example: input, model, input_type, truncate';

  @override
  String get mdlEdDefaultParametersJson => 'Default parameters (JSON)';

  @override
  String get mdlEdDefaultParametersJsonHint =>
      'For example: encoding_format: float';

  @override
  String get mdlEdOpenRouterRawMetadata => 'OpenRouter Raw Metadata';

  @override
  String get mdlEdOpenRouterRawMetadataFields =>
      'Includes id, canonical_slug, hugging_face_id, created, architecture, supported_parameters, default_parameters, supported_voices, knowledge_cutoff, expiration_date, and links';

  @override
  String get mdlEdReset => 'Reset';

  @override
  String get mdlEdCancel => 'Cancel';

  @override
  String get mdlEdOk => 'OK';

  @override
  String get tlCallDir => 'Dir';

  @override
  String get tlCallElapsed => 'Elapsed';

  @override
  String get tlCallExit => 'Exit';

  @override
  String get tlCallToolInput => 'Tool Input';

  @override
  String get tlCallCommand => 'command';

  @override
  String get tlCallArguments => 'arguments';

  @override
  String get tlCallToolOutput => 'Tool Output';

  @override
  String get tlCallNoOutputYet => 'No output yet';

  @override
  String get tlCallResult => 'result';

  @override
  String get tlCallStdout => 'stdout';

  @override
  String get tlCallStderr => 'stderr';

  @override
  String get tlCallArgumentsConstructing => 'Constructing arguments…';

  @override
  String get tlCallArgumentsConstructingHint =>
      'Arguments are still streaming from the model; the card will switch to its normal state once construction completes.';

  @override
  String get tlCallCollectedParameters => 'Collected';

  @override
  String get tlCallNoParametersYet => 'No arguments parsed yet';

  @override
  String get tlCallSubmitting => 'Submitting…';

  @override
  String get tlCallSubmittingHint =>
      'Arguments captured; handing off to the executor';

  @override
  String get tlCallThereIsNoToolOutputYet => 'There is no tool output yet.';

  @override
  String get tlCallViewInDialog => 'View in Dialog';

  @override
  String get tlCallEmptyContent => 'Empty content';

  @override
  String get fileMutationSection => 'File changes';

  @override
  String fileMutationFilesChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files changed',
      one: '1 file changed',
    );
    return '$_temp0';
  }

  @override
  String fileMutationFilesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String get fileMutationUndoAll => 'Undo all';

  @override
  String get fileMutationRefresh => 'Refresh';

  @override
  String get fileMutationCopyAllDiff => 'Copy all diffs';

  @override
  String get fileMutationCopyAllDiffDone => 'All diffs copied to clipboard';

  @override
  String get fileMutationRevealLedger => 'Reveal ledger.jsonl in file manager';

  @override
  String get fileMutationCopyPath => 'Copy file path';

  @override
  String get fileMutationPathCopied => 'Path copied';

  @override
  String fileMutationRevealMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'changes',
      one: 'change',
    );
    return '$count more $_temp0 hidden — tap to reveal next batch';
  }

  @override
  String get fileMutationRevealAll => 'Reveal all';

  @override
  String get fileMutationHistoryInspector => 'History inspector';

  @override
  String get fileMutationHistoryInspectorTitle => 'Session file history';

  @override
  String get fileMutationHistoryInspectorFilterHint => 'Filter by path...';

  @override
  String get fileMutationHistoryInspectorEmpty =>
      'No file changes match the current filter.';

  @override
  String get fileMutationHistoryInspectorZoomIn => 'Focus on this path';

  @override
  String get fileMutationHistoryInspectorZoomOut => 'Show all paths';

  @override
  String get fileMutationUndone => 'Undone';

  @override
  String get fileMutationCascadeUndone => 'Cascade undone';

  @override
  String get fileMutationUndoThis => 'Undo this change';

  @override
  String get fileMutationRedo => 'Redo';

  @override
  String get fileMutationUndoFailed => 'Undo failed';

  @override
  String get fileMutationRedoFailed => 'Redo failed';

  @override
  String get fileMutationSnapshotUnavailable => 'Content snapshot unavailable';

  @override
  String get tlCallTool => 'Tool';

  @override
  String get tlCallSkill => 'Skill';

  @override
  String get tlCallStopped => 'Stopped';

  @override
  String get tlCallStopRequest => 'Stop this tool call';

  @override
  String get tlCallBlocked => 'Blocked';

  @override
  String get tlCallRejected => 'Rejected';

  @override
  String get tlCallInvalid => 'Invalid';

  @override
  String get tlCallToolCall => 'Tool Call';

  @override
  String get tlCallRunning => 'Running';

  @override
  String get tlCallSucceeded => 'Succeeded';

  @override
  String get tlCallDenied => 'Denied';

  @override
  String get tlCallTimedOut => 'Timed Out';

  @override
  String get tlCallFailed => 'Failed';

  @override
  String get tlCallToolIsRunningWaitingForOutput =>
      'Tool is running. Waiting for output...';

  @override
  String get tlCallExpandToInspectToolOutput => 'Expand to inspect tool output';

  @override
  String get tlCallSelfLearning => 'Self-Learning';

  @override
  String get tlCallNudgeRecovered => 'Nudge recovered';

  @override
  String get tlCallProfileChanges => 'Profile Changes';

  @override
  String get tlCallMemoryChanges => 'Memory Changes';

  @override
  String get tlCallSkillChanges => 'Skill Changes';

  @override
  String get tlCallProfileDiff => 'Profile Diff';

  @override
  String get tlCallNoChanges => 'No changes';

  @override
  String get tlCallUnnamed => '(unnamed)';

  @override
  String get tlCallJustNow => 'just now';

  @override
  String get sessMetaCacheHitTrend => 'CACHE HIT RATE TREND';

  @override
  String get sessMetaCacheHitLast => 'latest';

  @override
  String get sessMetaCacheHitAvg => 'avg';

  @override
  String get sessMetaCacheHitMax => 'max';

  @override
  String get sessMetaCacheHitOverlayOn => 'Overlay other formula';

  @override
  String get sessMetaCacheHitOverlayOff => 'Hide overlay';

  @override
  String get sessMetaCacheHitFormulaClaude => 'Claude formula';

  @override
  String get sessMetaCacheHitFormulaOpenAi => 'OpenAI formula';

  @override
  String sessMetaCacheHitPoint(int index) {
    return 'Turn $index';
  }

  @override
  String get sessMetaMessages => 'Messages';

  @override
  String get sessMetaPromptBuilds => 'Prompt Builds';

  @override
  String get sessMetaCompressions => 'Compressions';

  @override
  String get sessMetaTotalTokens => 'Total Tokens';

  @override
  String get sessMetaMode => 'Mode';

  @override
  String get sessMetaRuntimeTools => 'Runtime Tools';

  @override
  String get sessMetaPending => 'Pending';

  @override
  String get sessMetaCurrentSessionMetadata => 'Current Session Metadata';

  @override
  String get sessMetaSessionOverview => 'Session Overview';

  @override
  String get sessMetaExtendedMetadata => 'Extended Metadata';

  @override
  String get sessMetaStatistics => 'Statistics';

  @override
  String get sessMetaUser => 'User';

  @override
  String get sessMetaAssistant => 'Assistant';

  @override
  String get sessMetaTool => 'Tool';

  @override
  String get sessMetaSkill => 'Skill';

  @override
  String get sessMetaCompression => 'Compression';

  @override
  String get sessMetaEnvironment => 'Environment';

  @override
  String get sessMetaCommandPolicy => 'Command Policy';

  @override
  String get sessMetaPromptMetadataIsNotAvailableYet =>
      'Prompt metadata is not available yet.';

  @override
  String get sessMetaWriteConfirmation => 'Write Confirmation';

  @override
  String get sessMetaRequired => 'Required';

  @override
  String get sessMetaNotRequired => 'Not required';

  @override
  String get sessMetaAllowRules => 'Allow Rules';

  @override
  String get sessMetaThereAreNoSurfacedAllowCommand =>
      'There are no surfaced allow command rules.';

  @override
  String get sessMetaRuntimeOrchestration => 'Runtime Orchestration';

  @override
  String get sessMetaStateSource => 'State Source';

  @override
  String get sessMetaGeneratedFromTheCurrentModelMcp =>
      'Generated from the current model, MCP/skills, and plan state';

  @override
  String get sessMetaTheLastPersistedRuntimeSnapshot =>
      'The last persisted runtime snapshot';

  @override
  String get sessMetaToolCatalogState => 'Tool Catalog State';

  @override
  String get sessMetaGateReason => 'Gate Reason';

  @override
  String get sessMetaRuntimeToolCount => 'Runtime Tool Count';

  @override
  String get sessMetaRefreshesNextRound => 'Refreshes next round';

  @override
  String get sessMetaRuntimeNotices => 'Runtime Notices';

  @override
  String get sessMetaCurrentRuntimeTools => 'Current Runtime Tools';

  @override
  String get sessMetaTaskTracking => 'Task Tracking';

  @override
  String get sessMetaCurrentTodos => 'Current Todos';

  @override
  String get sessMetaPlanRecords => 'Plan Records';

  @override
  String get sessMetaTodowriteReminder => 'TodoWrite Reminder';

  @override
  String get sessMetaTriggered => 'Triggered';

  @override
  String get sessMetaNotTriggered => 'Not triggered';

  @override
  String get sessMetaUnavailable => 'Unavailable';

  @override
  String get sessMetaReminderReason => 'Reminder Reason';

  @override
  String get sessMetaPlanHistory => 'Plan History';

  @override
  String get sessMetaRecentErrors => 'Recent Errors';

  @override
  String get sessMetaThereAreNoSessionErrorsTo =>
      'There are no session errors to review.';

  @override
  String get sessMetaLastPromptMetadata => 'Last Prompt Metadata';

  @override
  String get sessMetaClose => 'Close';

  @override
  String get sessMetaPendingApproval => 'Pending Approval';

  @override
  String get sessMetaInProgress => 'In Progress';

  @override
  String get sessMetaCompleted => 'Completed';

  @override
  String get sessMetaFailed => 'Failed';

  @override
  String get sessMetaCancelled => 'Cancelled';

  @override
  String get sessMetaCreated => 'Created';

  @override
  String get sessMetaUpdated => 'Updated';

  @override
  String get sessMetaErrorDetail => 'Error Detail';

  @override
  String get commonDetails => 'Details';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonViewDetails => 'View details';

  @override
  String get commonCopiedToClipboard => 'Copied to clipboard';

  @override
  String get structuredErrorWhy => 'Why:';

  @override
  String get structuredErrorTry => 'Try:';

  @override
  String get structuredErrorServerSays => 'Server says:';

  @override
  String get structuredErrorRaw => 'Raw:';

  @override
  String get sessMetaPresented => 'Presented';

  @override
  String get sessMetaThisSessionEndedEarlyRetryThe =>
      'This session ended early. Retry the request or continue with a more specific instruction.';

  @override
  String get sessMetaToolCallsStoppedForSafety =>
      'Tool Calls Stopped for Safety';

  @override
  String get sessMetaOpenhandStoppedThisSessionForSafety =>
      'OpenHand stopped this session for safety after too many sequential tool rounds. This stop happened in the session controller before the next tool could run, not because one specific tool execution failed. Ask the assistant to summarize the current progress or give a more specific next step.';

  @override
  String get sessMetaResponseInterrupted => 'Response Interrupted';

  @override
  String get sessMetaTheResponseWasInterruptedWhileStreaming =>
      'The response was interrupted while streaming and this session has stopped. Retry the request or continue with a new message.';

  @override
  String get sessMetaRequestFailed => 'Request Failed';

  @override
  String get sessMetaTheRequestFailedBeforeTheAssistant =>
      'The request failed before the assistant could continue. Check the configuration and retry, or send a new message.';

  @override
  String get sessMetaContinuationFailed => 'Continuation Failed';

  @override
  String get sessMetaTheSessionFailedWhileRequestingThe =>
      'The session failed while requesting the next assistant round after continuing execution. Completed steps and tool results were preserved. Reply with continue/retry, or check the configuration and try again.';

  @override
  String get sessMetaSafetyStop => 'Safety Stop';

  @override
  String get sessMetaStreamError => 'Stream Error';

  @override
  String get sessMetaRequestError => 'Request Error';

  @override
  String get sessMetaContinuationError => 'Continuation Error';

  @override
  String get sessMetaToolExecutionError => 'Tool Execution Error';

  @override
  String get sessMetaCompressionError => 'Compression Error';

  @override
  String get sessMetaPromptBlocked => 'Prompt Blocked';

  @override
  String get sessMetaTitleGenerationError => 'Title Generation Error';

  @override
  String get sessMetaSessionError => 'Session Error';

  @override
  String get auditNoData => 'No data';

  @override
  String get auditCopyJson => 'Copy JSON';

  @override
  String get auditCopiedToClipboard => 'Copied to clipboard';

  @override
  String get auditMessageAudit => 'Message Audit';

  @override
  String get auditClose => 'Close';

  @override
  String get auditOverview => 'Overview';

  @override
  String get auditMessageId => 'Message ID';

  @override
  String get auditSessionId => 'Session ID';

  @override
  String get auditRole => 'Role';

  @override
  String get auditKind => 'Kind';

  @override
  String get auditCharacterCount => 'Character Count';

  @override
  String get auditStreaming => 'Streaming';

  @override
  String get auditDeleted => 'Deleted';

  @override
  String get auditHasError => 'Has Error';

  @override
  String get auditTiming => 'Timing';

  @override
  String get auditStartedCreated => 'Started / Created';

  @override
  String get auditEnded => 'Ended';

  @override
  String get auditDurationMs => 'Duration (ms)';

  @override
  String get auditModelTokens => 'Model & Tokens';

  @override
  String get auditModelId => 'Model ID';

  @override
  String get auditModelLabel => 'Model Label';

  @override
  String get auditTotalTokens => 'Total Tokens';

  @override
  String get auditCacheHitRatio => 'Cache Hit Rate';

  @override
  String get auditPromptTokens => 'Prompt Tokens';

  @override
  String get auditCompletionTokens => 'Completion Tokens';

  @override
  String get auditTokenBreakdown => 'Token Breakdown';

  @override
  String get auditError => 'Error';

  @override
  String get auditContent => 'Content';

  @override
  String get auditFullComposedPromptThatWasActually =>
      'Full composed prompt that was actually sent to the AI for this round (system instructions, tool catalog, memory, history and user input).';

  @override
  String get auditWaitingForComposedPromptInjectionAuto =>
      'Waiting for composed prompt injection (auto-refreshes during streaming).';

  @override
  String get auditUserRawInput => 'User Raw Input';

  @override
  String get auditStructuredPromptTurns => 'Structured Prompt Turns';

  @override
  String get auditNone => 'None';

  @override
  String get auditPromptMetadata => 'Prompt Metadata';

  @override
  String get auditRequest => 'Request';

  @override
  String get auditMethod => 'Method';

  @override
  String get auditHeaders => 'Headers';

  @override
  String get auditNotCapturedEnableSettingsAiTelemetry =>
      'Not captured (enable Settings → AI → Telemetry Debug)';

  @override
  String get auditBodyQueryPath => 'Body / Query / Path';

  @override
  String get auditRawAiResponse => 'Raw AI Response';

  @override
  String get auditExpandRawResponse => 'Expand raw response';

  @override
  String get auditNotCapturedDebugDisabledOrResponse =>
      'Not captured: debug disabled or response unavailable';

  @override
  String get auditAttachments => 'Attachments';

  @override
  String get auditAttachmentList => 'Attachment list';

  @override
  String get auditNoAttachments => 'No attachments';

  @override
  String get auditFullMetadata => 'Full Metadata';

  @override
  String get auditMessageMetadata => 'Message metadata';

  @override
  String get auditSessionEnvironment => 'Session Environment';

  @override
  String get auditEnvironmentSnapshot => 'Environment snapshot';

  @override
  String get auditAuditSnapshotCopied => 'Audit snapshot copied';

  @override
  String get auditCopyAuditSnapshot => 'Copy Audit Snapshot';

  @override
  String get auditSessionMetadataSaved => 'Session metadata saved';

  @override
  String get auditSessionAudit => 'Session Audit';

  @override
  String get auditTemplate => 'Template';

  @override
  String get auditCreatedAt => 'Created At';

  @override
  String get auditUpdatedAt => 'Updated At';

  @override
  String get auditMessages => 'Messages';

  @override
  String get auditLastModel => 'Last Model';

  @override
  String get auditTitleEditable => 'Title (Editable)';

  @override
  String get auditSessionTitle => 'Session title';

  @override
  String get auditSaveTitle => 'Save Title';

  @override
  String get auditSessionMetadataEditableJson =>
      'Session Metadata (Editable JSON)';

  @override
  String get auditSaveWritesBackThroughTheSession =>
      'Save writes back through the session controller with live UI diff; removed keys are cleared.';

  @override
  String get auditSaveMetadata => 'Save Metadata';

  @override
  String get auditRuntimePromptMetadataReadOnly =>
      'Runtime Prompt Metadata (Read-only)';

  @override
  String get auditUsefulForPromptConstructionTroubleshooti =>
      'Useful for prompt-construction troubleshooting; auto-updated by runtime.';

  @override
  String get auditLastPromptMetadata => 'last_prompt_metadata';

  @override
  String get auditNoRuntimePromptMetadataYet =>
      'No runtime prompt metadata yet';

  @override
  String get auditEnvironment => 'Environment';

  @override
  String get auditErrorList => 'Error list';

  @override
  String get auditNoErrorsRecorded => 'No errors recorded';

  @override
  String get auditTapARowToInspectA =>
      'Tap a row to inspect a message; delete removes it from storage.';

  @override
  String get auditNoMessages => 'No messages';

  @override
  String get auditAudit => 'Audit';

  @override
  String get auditDelete => 'Delete';

  @override
  String get progExpFESelectOpenedFile => 'Select Opened File';

  @override
  String get progExpFEExpandSelected => 'Expand Selected';

  @override
  String get progExpFECollapseAll => 'Collapse All';

  @override
  String get progExpFETypeASymbolNameToSearch =>
      'Type a symbol name to search across files in the current workspace.';

  @override
  String get progExpFENoWorkspaceSymbolBackendIsAvailable =>
      'No workspace symbol backend is available for the current file.';

  @override
  String get progExpFENoMatchingWorkspaceSymbolsWereFound =>
      'No matching workspace symbols were found.';

  @override
  String get progExpFEFetchingWorkspaceSymbolsFailedConfirmTha =>
      'Fetching workspace symbols failed. Confirm that the active language server supports workspace/symbol.';

  @override
  String get progExpFEThisFileIsStillInLarge =>
      'This file is still in large-file preview mode, so the symbol bar is using local extraction to stay responsive.';

  @override
  String get progExpFENoLspSymbolBackendIsAvailable =>
      'No LSP symbol backend is available for this file, so the symbol bar fell back to local extraction.';

  @override
  String get progExpFETheLspServerReturnedAnEmpty =>
      'The LSP server returned an empty symbol list.';

  @override
  String get progExpFEFetchingLspSymbolsFailedSoThe =>
      'Fetching LSP symbols failed, so the symbol bar fell back to local extraction.';

  @override
  String get progExpFERenameSymbol => 'Rename Symbol';

  @override
  String get progExpFEReviewTheDiffForThisRename =>
      'Review the diff for this rename before deciding whether to apply it.';

  @override
  String get progExpFETheRenameWasCancelledAndNo =>
      'The rename was cancelled and no changes were applied.';

  @override
  String get progExpFETheSymbolAtTheCurrentCursor =>
      'The symbol at the current cursor position cannot be renamed.';

  @override
  String get progExpFETheLanguageServerDidNotReturn =>
      'The language server did not return any edits to apply.';

  @override
  String get progExpFECodeActions => 'Code Actions';

  @override
  String get progExpFENoCodeActionsAreAvailableAt =>
      'No code actions are available at the current cursor position.';

  @override
  String get progExpFEReviewTheDiffFromThisCode =>
      'Review the diff from this code action before applying it.';

  @override
  String get progExpFEIfTheLanguageServerCommandRequests =>
      'If the language-server command requests edits while running, those edits will also be previewed first.';

  @override
  String get progExpFETheCodeActionWasCancelledAnd =>
      'The code action was cancelled and no changes were applied.';

  @override
  String get progExpFEExecutedTheLanguageServerCommand =>
      'Executed the language-server command.';

  @override
  String get progExpFESomeLanguageServerRequestedEditsWere =>
      'Some language-server requested edits were skipped.';

  @override
  String get progExpFEThisCodeActionDidNotReturn =>
      'This code action did not return any applicable edits.';

  @override
  String get progExpFEQuickFix => 'Quick Fix';

  @override
  String get progExpFENoQuickFixesAreAvailableFor =>
      'No quick fixes are available for the hovered diagnostic.';

  @override
  String get progExpFENoCodeActionsAreAvailableFor =>
      'No code actions are available for the hovered diagnostic.';

  @override
  String get progExpFENoQuickFixesAreAvailableFor2 =>
      'No quick fixes are available for this diagnostic line.';

  @override
  String get progExpFETheCurrentFileIsStillLoading =>
      'The current file is still loading, so LSP actions are not available yet.';

  @override
  String get progExpFEThisFileIsStillInLarge2 =>
      'This file is still in large-file preview mode. Open the full editor before running LSP navigation.';

  @override
  String get progExpFETheCurrentFileIsStillLoading2 =>
      'The current file is still loading, so document-level edit actions are not available yet.';

  @override
  String get progExpFEThisFileIsStillInLarge3 =>
      'This file is still in large-file preview mode. Open the full editor before formatting.';

  @override
  String get progExpFEFormatDocument => 'Format Document';

  @override
  String get progExpFETheCurrentFileIsNotReady =>
      'The current file is not ready yet. Try again in a moment.';

  @override
  String get progExpFETheFormatterDidNotReturnAny =>
      'The formatter did not return any edits to apply.';

  @override
  String get progExpFEFormattingProducedTheSameContentSo =>
      'Formatting produced the same content, so no text changed.';

  @override
  String get progExpFEGoToDefinition => 'Go to Definition';

  @override
  String get progExpFENoDefinitionWasFoundAtThe =>
      'No definition was found at the current cursor position.';

  @override
  String get progExpFEMultipleDefinitionsWereFoundChooseA =>
      'Multiple definitions were found. Choose a target to navigate to.';

  @override
  String get progExpFEFindReferences => 'Find References';

  @override
  String get progExpFENoReferencesWereFoundAtThe =>
      'No references were found at the current cursor position.';

  @override
  String get progExpFEHoverInfo => 'Hover Info';

  @override
  String get progExpFEThereIsNoHoverInformationAt =>
      'There is no hover information at the current cursor position.';

  @override
  String get progExpFELspBackend => 'LSP Backend';

  @override
  String get progExpFEReResolveTheBackendForThe =>
      'Re-resolve the backend for the current file';

  @override
  String get progExpFEInspectBackendDetails => 'Inspect backend details';

  @override
  String get progExpFECloseEsc => 'Close (Esc)';

  @override
  String get progExpFEToggleComment => 'Toggle Comment';

  @override
  String get progExpFEThisLanguageDoesNotHaveA =>
      'This language does not have a configured comment strategy yet, so comment toggling is unavailable.';

  @override
  String get progExpFEGoToImplementation => 'Go to Implementation';

  @override
  String get progExpFESignatureHelp => 'Signature Help';

  @override
  String get progExpFEThereIsNoSignatureHelpAvailable =>
      'There is no signature help available at the current cursor position.';

  @override
  String get progExpFEPreviousMatch => 'Previous Match';

  @override
  String get progExpFENextMatch => 'Next Match';

  @override
  String get progExpFEMatchCase => 'Match Case';

  @override
  String get progExpFEShowReplace => 'Show Replace';

  @override
  String get progExpFEReplaceCurrent => 'Replace Current';

  @override
  String get progExpFEReplaceAll => 'Replace All';

  @override
  String get progExpFECurrentFileSymbols => 'Current File Symbols';

  @override
  String get progExpFEWorkspaceSymbols => 'Workspace Symbols';

  @override
  String get progExpFERefreshDiagnostics => 'Refresh diagnostics';

  @override
  String get progExpFESymbols => 'Symbols';

  @override
  String get progExpFESymbolNavigationShiftCmdCtrlO =>
      'Symbol navigation (Shift+Cmd/Ctrl+O)';

  @override
  String get progExpFEWorkspace => 'Workspace';

  @override
  String get progExpFEWorkspaceSymbolSearchCmdCtrlT =>
      'Workspace symbol search (Cmd/Ctrl+T)';

  @override
  String get progExpFEShowDiagnosticsForTheCurrentFile =>
      'Show diagnostics for the current file';

  @override
  String get progExpFEInspectTheLspBackendBoundTo =>
      'Inspect the LSP backend bound to the current file';

  @override
  String get progExpFEDef => 'Def';

  @override
  String get progExpFEGoToDefinitionF12CmdCtrl =>
      'Go to Definition (F12 / Cmd/Ctrl+B)';

  @override
  String get progExpFERefs => 'Refs';

  @override
  String get progExpFEFindReferencesShiftF12CmdCtrl =>
      'Find References (Shift+F12 / Cmd/Ctrl+Shift+B)';

  @override
  String get progExpFEHover => 'Hover';

  @override
  String get progExpFEHoverInfoCmdCtrlI => 'Hover Info (Cmd/Ctrl+I)';

  @override
  String get progExpFERename => 'Rename';

  @override
  String get progExpFERenameSymbolF2 => 'Rename Symbol (F2)';

  @override
  String get progExpFEActions => 'Actions';

  @override
  String get progExpFECodeActionsCmdCtrl => 'Code Actions (Cmd/Ctrl+.)';

  @override
  String get progExpFEFormat => 'Format';

  @override
  String get progExpFENoImplementationWasFoundAtThe =>
      'No implementation was found at the current cursor position.';

  @override
  String get progExpFEMultipleImplementationsFoundChooseATarge =>
      'Multiple implementations found. Choose a target to navigate to.';

  @override
  String get progExpFERefactor => 'Refactor';

  @override
  String get progExpFEReviewTheChangesBeforeApplying =>
      'Review the changes before applying.';

  @override
  String get progExpFESaveFile => 'Save file';

  @override
  String get progExpFECloseEditorReturnToSession =>
      'Close editor, return to session';

  @override
  String get progExpFEShowQuickFixesForThisDiagnostic =>
      'Show quick fixes for this diagnostic line';

  @override
  String get progExpFELargeFilePerformanceModeIsActive =>
      'Large-file performance mode is active: using a virtualized read-only preview to avoid full-document layout stalls.';

  @override
  String get progExpFEOpenFullEditorAnyway => 'Open full editor anyway';

  @override
  String get settingsShortcuts => 'Shortcuts';

  @override
  String get settingsConfigureKeyCombinationsForCommonActions =>
      'Configure key combinations for common actions. OpenHand currently supports up to four simultaneous keys.';

  @override
  String get settingsBuiltInTools => 'Built-in Tools';

  @override
  String get settingsCrons => 'Crons';

  @override
  String get settingsControlsRetentionAndColdStartCleanup =>
      'Controls retention and cold-start cleanup of cron execution history. The cleanup worker runs once per cold start with a hard timeout, single-flight lock and silentLog-only failures so it can never leak resources or loop indefinitely.';

  @override
  String get settingsHermesTalker => 'Hermes Talker';

  @override
  String get settingsConfigureHermesTalkerSelfLearningEvery =>
      'Configure Hermes Talker self-learning: every 5 minutes a system cron scans sessions from the last 7 days and dispatches a restricted sub-agent to update memory and skills in the background.';

  @override
  String get settingsEditor => 'Editor';

  @override
  String get settingsManagePerLanguageLspBackendsInstall =>
      'Manage per-language LSP backends, install roots, and download assistant settings. Saved mappings are applied directly to editor navigation, diagnostics, rename, and code actions.';

  @override
  String get settingsAppData => 'App Data';

  @override
  String get settingsPerResponseToolCallLimit => 'Per-Response Tool Call Limit';

  @override
  String get settingsSaveLimit => 'Save Limit';

  @override
  String get settingsSequentialToolRoundLimit => 'Sequential Tool Round Limit';

  @override
  String get settingsSessionSettings => 'Session Settings';

  @override
  String get settingsConfigureDefaultBehaviourForNewSessions =>
      'Configure default behaviour for new sessions, including timeouts, title fetching, default mode, and permissions.';

  @override
  String get settingsSendTimeoutS => 'Send Timeout (s)';

  @override
  String get settingsMaximumWaitTimeToEstablishThe =>
      'Maximum wait time to establish the HTTP connection and send the request. Default: 60 s.';

  @override
  String get settingsSaveTimeout => 'Save Timeout';

  @override
  String get settingsResponseTimeoutS => 'Response Timeout (s)';

  @override
  String get settingsMaximumWaitForACompleteResponse =>
      'Maximum wait for a complete response in non-streaming mode. Default: 120 s.';

  @override
  String get settingsStreamIdleTimeoutS => 'Stream Idle Timeout (s)';

  @override
  String get settingsMaximumIdleWaitBetweenStreamChunks =>
      'Maximum idle wait between stream chunks. Exceeding this causes \"Request timed out.\". Default: 120 s.';

  @override
  String get settingsAutoTitle => 'Auto Title Fetch';

  @override
  String get settingsWhenEnabledATitleIsAutomatically =>
      'When enabled, a session title is fetched after the first valid text message in a new session.';

  @override
  String get settingsTitleFetchMode => 'Title Fetch Mode';

  @override
  String get settingsTitleFetchModeDescription =>
      'Async does not block the first reply; sync fetches the title before sending the first AI request.';

  @override
  String get settingsTitleFetchModeAsync => 'Async';

  @override
  String get settingsTitleFetchModeSync => 'Sync';

  @override
  String get settingsDefaultSessionMode => 'Default Session Mode';

  @override
  String get settingsDefaultInteractionModeForNewSessions =>
      'Default interaction mode for new sessions: Chat or Plan.';

  @override
  String get settingsChat => 'Chat';

  @override
  String get settingsPlan => 'Plan';

  @override
  String get settingsDefaultFullAccess => 'Default Full Access';

  @override
  String get settingsWhenEnabledNewSessionsStartIn =>
      'When enabled, new sessions start in full-access mode, allowing the AI to execute file and command operations without per-action confirmation.';

  @override
  String get settingsUserProfile => 'User Profile';

  @override
  String get settingsMaintainAGlobalUserProfileLanguage =>
      'Maintain a global user profile (language style, focus areas, communication preferences). When non-empty, the profile is woven into the system prompt of every thread template so the AI feels personalised; self-learning incrementally refines it.';

  @override
  String get settingsModelProviderManagement => 'Model Provider Management';

  @override
  String get settingsAddSelectTestAndMaintainModel =>
      'Add, select, test, and maintain model provider configurations. Each provider can serve multiple models.';

  @override
  String get settingsCompressionTrigger => 'Compression Trigger';

  @override
  String get settingsOnceTheUncompressedHistoryInA =>
      'Once the uncompressed history in a thread exceeds this value, OpenHand creates a new summary checkpoint.';

  @override
  String get settingsToolCallOutputCompressionThreshold =>
      'Tool Call Output Compression Threshold';

  @override
  String get settingsWhenAToolCallReturnsMore =>
      'Used only when creating compression checkpoints: historical tool results over this threshold become structured summaries. Normal conversations always deliver complete results to the model. Defaults to 1024.';

  @override
  String get settingsDefaultsTo40IfOneAssistant =>
      'Defaults to 40. If one assistant response exceeds this many tool calls, OpenHand posts a warning message and stops the round safely.';

  @override
  String get settingsDefaultsTo24RoundsIfThe =>
      'Defaults to 24 rounds. If the assistant keeps requesting another tool round after each execution, OpenHand stops once this round limit is reached to prevent runaway tool loops.';

  @override
  String get settingsImageSizeLimit => 'Image Size Limit';

  @override
  String get settingsDefaultsTo1mbImageAttachmentsLarger =>
      'Defaults to 1MB. Image attachments larger than this cap are auto-compressed before the editor opens and stored within the limit, keeping sessions and prompts compact.';

  @override
  String get settingsCostControl => 'Cost Control';

  @override
  String get settingsReduceTokenCostsByFreezingThe =>
      'Reduce token costs by stabilizing the prompt static prefix and applying protocol-level cache hints. When enabled: the provider, model, and reasoning effort are locked once the AI begins responding to the first valid user message; Prompt Builder keeps system instructions, tool catalog, memory, and user instructions as stable leading sections where possible; Anthropic injects cache_control breakpoints, and OpenAI-compatible requests use stable cache affinity plus a messages-last body layout.';

  @override
  String get settingsEnableInputCache => 'Enable Input Cache';

  @override
  String get settingsDisabledByDefaultWhenEnabledEvery =>
      'Enabled by default. When disabled, OpenHand will not inject protocol-level cache hints or apply model-locking input-cache safeguards. To maximize hit rate, avoid frequent mid-session changes to tools, skills, MCP, memory, or instructions.';

  @override
  String get settingsCacheBreakpointUpdateMode =>
      'History Candidate Update Mode';

  @override
  String get settingsChooseTheSlidingUnitForThe =>
      'Stable, previous-request-tail, and current-tail anchors take priority. This setting only controls how remaining history candidates are selected.';

  @override
  String get settingsByMessageCountUserAssistant =>
      'By message count (user+assistant)';

  @override
  String get settingsByUserMessageCountOnly => 'By user-message count only';

  @override
  String get settingsByAccumulatedTokens => 'By accumulated tokens';

  @override
  String get settingsCacheBreakpointUpdateInterval =>
      'History Candidate Update Interval';

  @override
  String get settingsDefault10MeaningDependsOnThe =>
      'Default 10. Used only for automatic history candidates; its unit is message count, user-message count, or token threshold, depending on the mode above.';

  @override
  String get settingsSave => 'Save';

  @override
  String get settingsCacheBreakpointCount => 'Cache Breakpoint Count';

  @override
  String get settingsDefault4Range14Anthropic =>
      'Default 4, range 1-4. Anthropic spends the budget on the stable system/tool anchor, previous request tail, current tail, then history candidates, with at most 4 cache_control markers per request. OpenAI-compatible providers do not receive these markers.';

  @override
  String get settingsCommandSafety => 'Command Safety';

  @override
  String get settingsControlWriteCommandConfirmationForBash =>
      'Control write-command confirmation for bash and manage deny rules in one place.';

  @override
  String get settingsWriteCommandConfirmation => 'Write Command Confirmation';

  @override
  String get settingsEnabledByDefaultWhenTheAi =>
      'Enabled by default. When the AI tries to run a write-like bash command, OpenHand will ask for your confirmation first.';

  @override
  String get settingsAllowCommandList => 'Allow Command List';

  @override
  String get settingsMatchingWriteLikeBashCommandsSkip =>
      'Matching write-like bash commands skip the confirmation dialog and run immediately. Only use this for stable command patterns you explicitly trust.';

  @override
  String get settingsAddAllowRule => 'Add Allow Rule';

  @override
  String get settingsNoAllowRulesConfigured => 'No allow rules configured';

  @override
  String get settingsAddARuleToLetMatching =>
      'Add a rule to let matching write commands bypass confirmation.';

  @override
  String get settingsDenyCommandList => 'Deny Command List';

  @override
  String get settingsMatchingBashCommandsAreBlockedBefore =>
      'Matching bash commands are blocked before execution and the denial result is returned to the model instead. Supports regex and simple wildcard patterns such as `rm *`.';

  @override
  String get settingsAddRule => 'Add Rule';

  @override
  String get settingsNoDenyRulesConfigured => 'No deny rules configured';

  @override
  String get settingsAddARuleToBlockMatching =>
      'Add a rule to block matching bash commands before they run.';

  @override
  String get settingsTelemetry => 'Telemetry';

  @override
  String get settingsWhenEnabledOpenhandCapturesRawAi =>
      'When enabled, OpenHand captures raw AI responses, request parameters, timings and errors so you can inspect them from message/session audit dialogs.';

  @override
  String get settingsDebugMode => 'Debug Mode';

  @override
  String get settingsOffByDefaultWhenEnabledEvery =>
      'Off by default. When enabled, every message card exposes an Audit pill on hover/focus and each session toolbar shows a session-level Audit action.';

  @override
  String get settingsCaptureRawPayload => 'Capture Raw Payload';

  @override
  String get settingsEnabledByDefaultOnlyActiveWhen =>
      'Enabled by default. Only active when debug mode is on. Attaches the raw JSON/SSE chunks to message metadata for auditing.';

  @override
  String get settingsCaptureEnvironment => 'Capture Environment';

  @override
  String get settingsOffByDefaultOnlyActiveWhen =>
      'Off by default. Only active when debug mode is on. Attaches working directory, platform details and process environment variables (may contain secrets) to message metadata — enable with care.';

  @override
  String get settingsShortcutBindings => 'Shortcut Bindings';

  @override
  String get settingsClickRecordThenPressTheNew =>
      'Click record, then press the new key combination to update a binding. Model and session switching wrap around automatically.';

  @override
  String get settingsShortcutRecord => 'Record';

  @override
  String get settingsShortcutResetToDefault => 'Reset to default';

  @override
  String get settingsShortcutMaxKeysError =>
      'OpenHand supports up to four simultaneous keys.';

  @override
  String get settingsShortcutRecorderBody =>
      'Press the new key combination to update this binding. OpenHand supports up to four simultaneous keys.';

  @override
  String get settingsShortcutRecorderTip =>
      'Tip: include at least one non-modifier key such as Enter, P, or an arrow key.';

  @override
  String get settingsAutoCleanupExecutionHistory =>
      'Auto-cleanup execution history';

  @override
  String get settingsOnEveryColdStartAnAsync =>
      'On every cold start, an async worker runs once to delete history older than the retention window. The worker is single-flight, has a hard timeout, and silently logs failures so it can never block the UI or loop indefinitely.';

  @override
  String get settingsEnableSelfLearning => 'Enable self-learning';

  @override
  String get settingsWhenOffTheSchedulerSkipsEvery =>
      'When off, the scheduler skips every Hermes Talker session. The system cron entry is preserved but never dispatches a sub-agent.';

  @override
  String get settingsShowSelfLearningMessages => 'Show self-learning messages';

  @override
  String get settingsWhenOffSelfLearningCardsAre =>
      'When off, \"self-learning\" cards are hidden from the chat transcript (background learning still runs). Defaults to on.';

  @override
  String get settingsToolCatalogOverview => 'Tool Catalog Overview';

  @override
  String get settingsResetAll => 'Reset All';

  @override
  String get settingsEnableAll => 'Enable All';

  @override
  String get settingsDisableAll => 'Disable All';

  @override
  String get settingsNoBuiltInToolConfigurations =>
      'No built-in tool configurations';

  @override
  String get settingsClickResetAllToRestoreThe =>
      'Click \"Reset All\" to restore the default tool list.';

  @override
  String get settingsResetBuiltInToolConfigs => 'Reset Built-in Tool Configs';

  @override
  String get settingsCancel => 'Cancel';

  @override
  String get settingsReset => 'Reset';

  @override
  String get settingsDeleteCustomTool => 'Delete Custom Tool';

  @override
  String get settingsDelete => 'Delete';

  @override
  String get settingsSendTimeoutSaved => 'Send timeout saved.';

  @override
  String get settingsResponseTimeoutSaved => 'Response timeout saved.';

  @override
  String get settingsStreamIdleTimeoutSaved => 'Stream idle timeout saved.';

  @override
  String get settingsCacheBreakpointUpdateIntervalSaved =>
      'History candidate update interval saved';

  @override
  String get settingsCacheBreakpointCountSaved =>
      'Cache breakpoint count saved';

  @override
  String get settingsCacheBreakpointPositions => 'History Cache Candidates';

  @override
  String get settingsCacheBreakpointPositionsSaved =>
      'History cache candidates saved';

  @override
  String get cacheBarTopDescription =>
      'The colored bands illustrate prompt structure only. P-pins are candidate positions in message history; the dashed pin at the right is the current-request tail anchor. Stable and rolling tail anchors take priority before remaining candidates.';

  @override
  String get cacheBarSectionSysLabel => '[0] System';

  @override
  String get cacheBarSectionDevLabel => '[1] Developer';

  @override
  String get cacheBarSectionToolsLabel => '[2] Tools';

  @override
  String get cacheBarSectionStateLabel => '[3s/3d] State';

  @override
  String get cacheBarSectionMemoryLabel => '[4] Memory';

  @override
  String get cacheBarSectionUserInstLabel => '[4.5] Inst.';

  @override
  String get cacheBarSectionSummaryLabel => '[5] Summary';

  @override
  String get cacheBarSectionHistoryLabel => 'History';

  @override
  String get cacheBarSectionLatestLabel => 'Tail / latest';

  @override
  String get cacheBarSectionSysSummary =>
      'Template system instructions, workspace instructions and runtime environment snapshot (OS / cwd / repo digest).';

  @override
  String get cacheBarSectionSysCacheHint =>
      'Cache-friendly: highly stable across turns — ideal first breakpoint.';

  @override
  String get cacheBarSectionDevSummary =>
      'Behavioural rules from the active prompt template (output format & guardrails).';

  @override
  String get cacheBarSectionDevCacheHint =>
      'Cache-friendly: rarely changes within a session.';

  @override
  String get cacheBarSectionToolsSummary =>
      'Built-in tool catalog, MCP capabilities and skill loaders the model can call (with DSML invocation rules).';

  @override
  String get cacheBarSectionToolsCacheHint =>
      'Cache-friendly: stable unless tool registry changes.';

  @override
  String get cacheBarSectionStateSummary =>
      'Static + dynamic session state, focus context and other volatile tail system blocks that sit after history in the current prompt layout.';

  @override
  String get cacheBarSectionStateCacheHint =>
      'Mostly volatile: plan/todo/focus/reminder changes can invalidate this tail region without disturbing the earlier stable prefix.';

  @override
  String get cacheBarSectionMemorySummary =>
      'Long-term user memory facts integrated as tacit knowledge.';

  @override
  String get cacheBarSectionMemoryCacheHint =>
      'Mostly stable: changes only when memory entries are edited.';

  @override
  String get cacheBarSectionUserInstSummary =>
      'Reusable prompt fragments authored by the user (project-level guidance).';

  @override
  String get cacheBarSectionUserInstCacheHint =>
      'Stable: edited rarely; safe to anchor a breakpoint after this band.';

  @override
  String get cacheBarSectionSummarySummary =>
      'Compressed summary of older conversations + recent chat snippets.';

  @override
  String get cacheBarSectionSummaryCacheHint =>
      'Slowly evolving: refreshed when compression runs.';

  @override
  String get cacheBarSectionHistorySummary =>
      'Past user / assistant / tool turns within the current session.';

  @override
  String get cacheBarSectionHistoryCacheHint =>
      'Append-only: mid-history breakpoints survive new turns at the tail.';

  @override
  String get cacheBarSectionLatestSummary =>
      'The latest-turn payload near the prompt tail, including the current user turn and per-turn volatile reminder content.';

  @override
  String get cacheBarSectionLatestCacheHint =>
      'Always changing: the current tail anchor covers this region while the previous tail anchor preserves continuity.';

  @override
  String get cacheBarDynamicTooltip =>
      'Current-request tail anchor — always follows the latest message.';

  @override
  String get cacheBarDynamicSuffix => '(current tail)';

  @override
  String get cacheBarResetEven => 'Reset to even';

  @override
  String get settingsAiBudgetUsdPerSession => 'Per-session budget (USD)';

  @override
  String get settingsAiBudgetUsdPerSessionBody =>
      '0 disables the alert. When the cumulative estimated cost of a session exceeds this cap, the session metadata dialog highlights the total in a warning color. This is a soft reminder only — it never interrupts the conversation or blocks sending.';

  @override
  String get settingsAiBudgetUsdPerSessionInvalid =>
      'Please enter a non-negative number between 0 and 100000.';

  @override
  String get settingsAiBudgetUsdPerSessionSaved => 'Per-session budget saved';

  @override
  String sessionMetadataOverBudgetNotice(String total, String budget) {
    return 'Estimated cost $total for the current session has exceeded the budget $budget. This is a soft reminder only — sending is not affected.';
  }

  @override
  String get settingsEnterAToolCallLimitGreater =>
      'Enter a tool call limit greater than 0.';

  @override
  String get settingsThePerResponseToolCallLimit =>
      'The per-response tool call limit has been saved.';

  @override
  String get settingsEnterASequentialToolRoundLimit =>
      'Enter a sequential tool round limit greater than 0.';

  @override
  String get settingsTheSequentialToolRoundLimitHas =>
      'The sequential tool round limit has been saved.';

  @override
  String get settingsDeleteDenyRule => 'Delete Deny Rule';

  @override
  String get settingsTheDenyCommandRuleHasBeen =>
      'The deny command rule has been deleted.';

  @override
  String get settingsDeleteAllowRule => 'Delete Allow Rule';

  @override
  String get settingsTheAllowCommandRuleHasBeen =>
      'The allow command rule has been deleted.';

  @override
  String get settingsTheShortcutHasBeenUpdated =>
      'The shortcut has been updated.';

  @override
  String get settingsTheEditorShortcutHasBeenUpdated =>
      'The editor shortcut has been updated.';

  @override
  String get settingsSendMessage => 'Send Message';

  @override
  String get settingsCollapseOrExpandComposer => 'Collapse or Expand Composer';

  @override
  String get settingsPreviousModel => 'Previous Model';

  @override
  String get settingsNextModel => 'Next Model';

  @override
  String get settingsToggleAutoFollow => 'Toggle Auto Follow';

  @override
  String get settingsPreviousSession => 'Previous Session';

  @override
  String get settingsNextSession => 'Next Session';

  @override
  String get settingsSaveFile => 'Save File';

  @override
  String get settingsTriggerCompletion => 'Trigger Completion';

  @override
  String get settingsShowSignatureHelp => 'Show Signature Help';

  @override
  String get settingsFind => 'Find';

  @override
  String get settingsFindAndReplace => 'Find and Replace';

  @override
  String get settingsGoToLine => 'Go to Line';

  @override
  String get settingsDocumentSymbols => 'Document Symbols';

  @override
  String get settingsWorkspaceSymbols => 'Workspace Symbols';

  @override
  String get settingsGoToDefinition => 'Go to Definition';

  @override
  String get settingsFindReferences => 'Find References';

  @override
  String get settingsGoToImplementation => 'Go to Implementation';

  @override
  String get settingsShowHoverInfo => 'Show Hover Info';

  @override
  String get settingsRenameSymbol => 'Rename Symbol';

  @override
  String get settingsCodeActions => 'Code Actions';

  @override
  String get settingsFormatDocument => 'Format Document';

  @override
  String get settingsDefaultsToCtrlEnterAndTriggers =>
      'Defaults to Ctrl + Enter and triggers the send button when the chat composer is ready.';

  @override
  String get settingsDefaultsToCtrlPForQuickly =>
      'Defaults to Ctrl + P for quickly collapsing or expanding the composer.';

  @override
  String get settingsDefaultsToCtrlLeftAndWraps =>
      'Defaults to Ctrl + Left and wraps around to the last model when needed.';

  @override
  String get settingsDefaultsToCtrlRightAndWraps =>
      'Defaults to Ctrl + Right and wraps around to the first model when needed.';

  @override
  String get settingsDefaultsToCtrlSForToggling =>
      'Defaults to Ctrl + S for toggling auto follow.';

  @override
  String get settingsDefaultsToCtrlUpAndWraps =>
      'Defaults to Ctrl + Up and wraps to the end of the session list.';

  @override
  String get settingsDefaultsToCtrlDownAndWraps =>
      'Defaults to Ctrl + Down and wraps to the start of the session list.';

  @override
  String get settingsUndoLastFileMutation => 'Undo last file mutation';

  @override
  String get settingsDefaultsToCtrlShiftZForUndo =>
      'Defaults to Ctrl + Shift + Z; reverts the most recent file mutation in the current session.';

  @override
  String get auditDeleteMessage => 'Delete Message';

  @override
  String get auditDeleteThisMessageThisCannotBe =>
      'Delete this message? This cannot be undone.';

  @override
  String get auditCancel => 'Cancel';

  @override
  String get settingsManageTheBuiltInAiTools =>
      'Manage the built-in AI tools. Adjust each tool\'s enabled state, name, description, schema, priority, sort order, load strategy, and other parameters.';

  @override
  String get settingsManageTheLocalFilesAndDatabase =>
      'Manage the local files and database tables OpenHand owns on disk. Every cleanup runs on background workers — the UI thread stays responsive — and requires explicit second confirmation.';

  @override
  String get settingsThisWillRestoreAllBuiltIn =>
      'This will restore all built-in tool configurations to factory defaults, including name, description, schema overrides, priority, sort order, and load strategy. This cannot be undone.';

  @override
  String get tlCallUnwrap => 'Unwrap';

  @override
  String get tlCallWrapLines => 'Wrap Lines';

  @override
  String get tlCallViewCompressedContent => 'View Compressed Content';

  @override
  String get tlCallViewFullContent => 'View Full Content';

  @override
  String get tlCallPreparing => 'Preparing';

  @override
  String get tlCallPreparingAlt => 'Preparing';

  @override
  String get tlCallRunningAlt => 'Running';

  @override
  String get tlCallCompleted => 'Completed';

  @override
  String get tlCallCompletedAlt => 'Completed';

  @override
  String get tlCallTimedOutAlt => 'Timed Out';

  @override
  String get tlCallFailedAlt => 'Failed';

  @override
  String tlCallFailedToOpenFileLocationError(Object error) {
    return 'Failed to open file location: $error';
  }

  @override
  String tlCallMemoryitemsLengthMemoriesUpdated(Object memoryItems_length) {
    return '$memoryItems_length memories updated';
  }

  @override
  String tlCallProfileitemsLengthProfileChanges(Object profileItems_length) {
    return '$profileItems_length profile changes';
  }

  @override
  String tlCallSkillitemsLengthSkillsUpdated(Object skillItems_length) {
    return '$skillItems_length skills updated';
  }

  @override
  String get tlCallAiThinkingStreaming => 'AI Thinking (streaming)';

  @override
  String get tlCallAiThinking => 'AI Thinking';

  @override
  String get tlCallAiResponseStreaming => 'AI Response (streaming)';

  @override
  String get tlCallAiResponse => 'AI Response';

  @override
  String tlCallAndItemsLength3More(Object items_length_3, Object items_length) {
    return ' and $items_length_3 more';
  }

  @override
  String tlCallSecondsSAgo(Object seconds) {
    return '${seconds}s ago';
  }

  @override
  String tlCallMinutesMAgo(Object minutes) {
    return '${minutes}m ago';
  }

  @override
  String tlCallHoursHAgo(Object hours) {
    return '${hours}h ago';
  }

  @override
  String tlCallDaysDAgo(Object days) {
    return '${days}d ago';
  }

  @override
  String sessMetaPlanPlanindex(Object planIndex) {
    return 'Plan #$planIndex';
  }

  @override
  String sessMetaTheCurrentSequentialToolRoundLimit(Object configuredLimit) {
    return ' The current sequential tool round limit is $configuredLimit.';
  }

  @override
  String auditInvalidJsonErrorMessage(Object error_message) {
    return 'Invalid JSON: $error_message';
  }

  @override
  String auditSaveFailedError(Object error) {
    return 'Save failed: $error';
  }

  @override
  String auditRecentErrorsSessionRecenterrorsLength(
    Object session_recentErrors_length,
  ) {
    return 'Recent Errors ($session_recentErrors_length)';
  }

  @override
  String auditMessagesSessionMessagesLength(Object session_messages_length) {
    return 'Messages ($session_messages_length)';
  }

  @override
  String progExpFEAppliedEditsLengthFormattingEdits(Object edits_length) {
    return 'Applied $edits_length formatting edits.';
  }

  @override
  String progExpFEFormatTheCurrentFileFormatshortcut(Object formatShortcut) {
    return 'Format the current file ($formatShortcut)';
  }

  @override
  String progExpFENoCodeactionkindRefactoringIsAvailableAt(
    Object codeActionKind,
  ) {
    return 'No \"$codeActionKind\" refactoring is available at the current position.';
  }

  @override
  String get progExpFEHideFileBrowser => 'Hide file browser';

  @override
  String get progExpFEShowFileBrowser => 'Show file browser';

  @override
  String settingsRetentionWindowRetentionDayS(Object retention) {
    return 'Retention window: $retention day(s)';
  }

  @override
  String settingsRangeMinrMaxrDaysDefault7(Object minR, Object maxR) {
    return 'Range $minR–$maxR days; default 7. Takes effect on the next cold start.';
  }

  @override
  String settingsConcurrentWorkersConcurrency(Object concurrency) {
    return 'Concurrent workers: $concurrency';
  }

  @override
  String settingsCapsHowManySessionsCanBe(Object minC, Object maxC) {
    return 'Caps how many sessions can be dispatched in parallel per tick ($minC–$maxC). Defaults to 5.';
  }

  @override
  String settingsSortedLengthBuiltInToolsEnabledcount(
    Object sorted_length,
    Object enabledCount,
  ) {
    return '$sorted_length built-in tools, $enabledCount enabled. Adjust name, description, schema, priority, sort order, and load strategy for each.';
  }

  @override
  String settingsAreYouSureYouWantTo(Object config_effectiveName) {
    return 'Are you sure you want to delete \"$config_effectiveName\"? This cannot be undone.';
  }

  @override
  String settingsEnterAValueBetweenMinAnd(Object min, Object max) {
    return 'Enter a value between $min and $max seconds.';
  }

  @override
  String settingsPleaseEnterAnIntegerBetweenAppsettingssn(
    Object AppSettingsSnapshot_minAiInputCacheUpdateInterval,
    Object AppSettingsSnapshot_maxAiInputCacheUpdateInterval,
  ) {
    return 'Please enter an integer between $AppSettingsSnapshot_minAiInputCacheUpdateInterval and $AppSettingsSnapshot_maxAiInputCacheUpdateInterval';
  }

  @override
  String settingsPleaseEnterAnIntegerBetweenAppsettingssn2(
    Object AppSettingsSnapshot_minAiInputCacheBreakpointCount,
    Object AppSettingsSnapshot_maxAiInputCacheBreakpointCount,
  ) {
    return 'Please enter an integer between $AppSettingsSnapshot_minAiInputCacheBreakpointCount and $AppSettingsSnapshot_maxAiInputCacheBreakpointCount';
  }

  @override
  String settingsDragTheThumbcountThumbsToPosition(Object thumbCount) {
    return 'Drag $thumbCount points to set history candidates (0%-100%). Stable and rolling tail anchors use the budget first; the rightmost point is fixed to the current request tail.';
  }

  @override
  String get settingsTheDenyCommandRuleHasBeen2 =>
      'The deny command rule has been updated.';

  @override
  String get settingsTheAllowCommandRuleHasBeen2 =>
      'The allow command rule has been updated.';

  @override
  String settingsDefaultsToDefaultlabelAndSavesThe(Object defaultLabel) {
    return 'Defaults to $defaultLabel and saves the current file.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndOpensThe(Object defaultLabel) {
    return 'Defaults to $defaultLabel and opens the completion popup on demand.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsMethod(Object defaultLabel) {
    return 'Defaults to $defaultLabel and shows method signatures, parameter details, and summary docs for the current call site.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe(Object defaultLabel) {
    return 'Defaults to $defaultLabel and toggles the find panel.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe2(Object defaultLabel) {
    return 'Defaults to $defaultLabel and toggles the replace panel.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe3(Object defaultLabel) {
    return 'Defaults to $defaultLabel and toggles the go-to-line panel.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe4(Object defaultLabel) {
    return 'Defaults to $defaultLabel and toggles the symbol list for the current file.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe5(Object defaultLabel) {
    return 'Defaults to $defaultLabel and toggles the workspace symbol search panel.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndJumpsTo(Object defaultLabel) {
    return 'Defaults to $defaultLabel and jumps to the current symbol definition.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndFindsReferences(Object defaultLabel) {
    return 'Defaults to $defaultLabel and finds references for the current symbol.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndJumpsTo2(Object defaultLabel) {
    return 'Defaults to $defaultLabel and jumps to the current implementation.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsType(Object defaultLabel) {
    return 'Defaults to $defaultLabel and shows type or documentation info at the current position.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndStartsRename(Object defaultLabel) {
    return 'Defaults to $defaultLabel and starts rename for the current symbol.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsAvailable(Object defaultLabel) {
    return 'Defaults to $defaultLabel and shows available code actions.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndFormatsThe(Object defaultLabel) {
    return 'Defaults to $defaultLabel and formats the current programming file; Shift+Tab still outdents first when a multi-line selection is active.';
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
    return 'Resolved $lspName for the current file.\nProject language: $projLang\nCurrent file language: $fileLang\n$modeLine\n$sdkSourceLine\n$lspSourceLine\nWorkspace: $rootPath\nCommand: $command';
  }

  @override
  String get settingsReduceMotionLabel => 'Reduce motion';

  @override
  String get settingsReduceMotionBody =>
      'When enabled, custom and built-in animations are skipped (durations collapse to zero). Pairs with the system Reduce Motion accessibility setting.';

  @override
  String get mcpToolSearchReplayLastCancelAction => 'Replay last cancel';

  @override
  String get mcpToolSearchReplayLastCancelToastFired =>
      'Replayed last cancelled load';

  @override
  String get mcpToolSearchReplayLastCancelToastEmpty => 'Nothing to replay';

  @override
  String get aiThrottleSettingsLabel => 'Throttle Settings';

  @override
  String get aiThrottleSettingsBody =>
      'Unified streaming throttle: master switch, auto mode, char/card rates, duration.';

  @override
  String get webReverseVitalsInstalling => 'Installing observers…';

  @override
  String get webReverseVitalsResetting => 'Resetting…';

  @override
  String get webReverseVitalsReportCopied => 'Report JSON copied';

  @override
  String get webReverseVitalsTitle => 'Web Vitals';

  @override
  String get webReverseVitalsSubtitle =>
      'PerformanceObserver · LCP / CLS / INP / FCP / TTFB · live';

  @override
  String get webReverseVitalsCopyJson => 'Copy JSON';

  @override
  String get webReverseVitalsReset => 'Reset';

  @override
  String get webReverseVitalsClose => 'Close';

  @override
  String get webReverseVitalsThresholdsHint =>
      'Thresholds per web.dev. After reset, reload or interact to retrigger LCP / event samples.';

  @override
  String get webReverseIssuesCopied => 'Issue JSON copied';

  @override
  String get webReverseIssuesTitle => 'Issues';

  @override
  String get webReverseIssuesSubtitle => 'Audits.issueAdded · live aggregator';

  @override
  String get webReverseIssuesClearBuffer => 'Clear buffer';

  @override
  String get webReverseIssuesClose => 'Close';

  @override
  String get webReverseIssuesFilterHint =>
      'Filter by code / URL / description…';

  @override
  String get webReverseIssuesEmptyBuffer =>
      'No issues reported yet. Interact with the page.';

  @override
  String get webReverseIssuesNoMatch => 'No matching issue.';

  @override
  String get webReverseIssuesCopyJson => 'Copy JSON';

  @override
  String get webReverseIssuesCollapse => 'Collapse';

  @override
  String get webReverseIssuesExpand => 'Expand';

  @override
  String get webReverseIssuesSubscribed => 'Subscribed to Audits.issueAdded';

  @override
  String get webReverseIssuesAuditsNotReady => 'Audits domain not ready';

  @override
  String get webReverseRenderingResetSuccess => 'Rendering overrides reset';

  @override
  String get webReverseRenderingTitle => 'Rendering';

  @override
  String get webReverseRenderingSubtitle =>
      'Paint · Layout shift · Layers · FPS · media · CPU throttle';

  @override
  String get webReverseRenderingResetAll => 'Reset all';

  @override
  String get webReverseRenderingClose => 'Close';

  @override
  String get webReverseRenderingSectionOverlays => 'Overlays';

  @override
  String get webReverseRenderingPaintFlashingDesc =>
      'Highlight repainted regions';

  @override
  String get webReverseRenderingLayoutShiftDesc => 'Visualize CLS regions';

  @override
  String get webReverseRenderingLayerBordersDesc => 'Composited layer borders';

  @override
  String get webReverseRenderingScrollBottleneckDesc => 'Slow-scroll regions';

  @override
  String get webReverseRenderingHitTestDesc => 'Element hit-test borders';

  @override
  String get webReverseRenderingFpsDesc => 'Live FPS overlay';

  @override
  String get webReverseRenderingWebVitalsDesc =>
      'LCP / CLS / INP floating layer';

  @override
  String get webReverseRenderingSectionPerf => 'Performance emulation';

  @override
  String get webReverseRenderingSectionMedia => 'Media emulation';

  @override
  String get webReverseRenderingLabelColorScheme => 'Color scheme';

  @override
  String get webReverseRenderingLabelReducedMotion => 'Reduced motion';

  @override
  String get webReverseRenderingLabelMediaType => 'Media type';

  @override
  String get webReverseRenderingCpuThrottling => 'CPU throttling';

  @override
  String get webReverseAnimationsTitle => 'Animations';

  @override
  String get webReverseAnimationsSubtitle =>
      'CDP Animation.setPlaybackRate + document.getAnimations() snapshot';

  @override
  String get webReverseAnimationsCopyJson => 'Copy JSON';

  @override
  String get webReverseAnimationsRefresh => 'Refresh';

  @override
  String get webReverseAnimationsGlobalRate => 'Global rate';

  @override
  String get webReverseAnimationsPauseSymbol => 'Pause';

  @override
  String get webReverseAnimationsBulkPause => 'Pause all';

  @override
  String get webReverseAnimationsBulkResume => 'Resume all';

  @override
  String get webReverseAnimationsBulkCancel => 'Cancel all';

  @override
  String get webReverseAnimationsEmptyState =>
      'No active animations. Trigger one and refresh.';

  @override
  String get webReverseAnimationsRowPause => 'Pause';

  @override
  String get webReverseAnimationsRowPlay => 'Play';

  @override
  String get webReverseAnimationsRowCancel => 'Cancel';

  @override
  String get webReverseAnimationsClose => 'Close';

  @override
  String get webReverseAnimationsNoSnapshot => 'no snapshot returned';

  @override
  String get webReverseAnimationsMalformedSnapshot => 'malformed snapshot';

  @override
  String get webReverseAnimationsJsonCopied => 'JSON copied';

  @override
  String webReverseAnimationsSetFailed(String error) {
    return 'setPlaybackRate failed: $error';
  }

  @override
  String webReverseAnimationsRateNow(String rate) {
    return 'global rate = ${rate}x';
  }

  @override
  String webReverseAnimationsSetError(String error) {
    return 'error: $error';
  }

  @override
  String webReverseAnimationsBrowserError(String error) {
    return 'browser error: $error';
  }

  @override
  String webReverseAnimationsSnapshotCount(int count) {
    return '$count active animation(s)';
  }

  @override
  String webReverseAnimationsSnapshotFailed(String error) {
    return 'snapshot failed: $error';
  }

  @override
  String webReverseAnimationsBulkInvoked(String method, int count) {
    return '$method invoked on $count animation(s)';
  }

  @override
  String webReverseAnimationsBulkError(String method, String error) {
    return '$method error: $error';
  }

  @override
  String get webReverseHarTitle => 'HAR Persistence';

  @override
  String get webReverseHarSubtitle =>
      'Save now / Load back / Periodic rotation';

  @override
  String get webReverseHarOpenSaveDialogFail => 'Failed to open save dialog';

  @override
  String get webReverseHarExporting => 'Exporting...';

  @override
  String get webReverseHarExportFailedNoDraft => 'Export failed (no HAR draft)';

  @override
  String get webReverseHarExportFailed => 'Export failed';

  @override
  String get webReverseHarWrotePrefix => 'Wrote: ';

  @override
  String get webReverseHarSaved => 'HAR saved';

  @override
  String get webReverseHarExportErrorShort => 'Export error';

  @override
  String get webReverseHarOpenFileDialogFail => 'Failed to open file dialog';

  @override
  String get webReverseHarParsing => 'Parsing HAR...';

  @override
  String get webReverseHarModeMerge => 'merge';

  @override
  String get webReverseHarModeReplace => 'replace';

  @override
  String get webReverseHarLoaded => 'HAR loaded';

  @override
  String get webReverseHarLoadErrorShort => 'Load error';

  @override
  String get webReverseHarSelect => 'Select';

  @override
  String get webReverseHarChooseFolderFirst => 'Choose a folder first';

  @override
  String get webReverseHarAutoStarted => 'Auto-rotate started';

  @override
  String get webReverseHarAutoStopped => 'Auto-rotate stopped';

  @override
  String get webReverseHarSessionStatus => 'Session status';

  @override
  String get webReverseHarManual => 'Manual';

  @override
  String get webReverseHarSaveNow => 'Save HAR now';

  @override
  String get webReverseHarLoadExternal => 'Load external HAR';

  @override
  String get webReverseHarMergeLabel => 'Merge (no clear)';

  @override
  String get webReverseHarLastHarPrefix => 'Last HAR: ';

  @override
  String get webReverseHarAutoRotate => 'Auto-rotate';

  @override
  String get webReverseHarIntervalLabel => 'Interval:';

  @override
  String get webReverseHarChooseFolder => 'Choose folder';

  @override
  String get webReverseHarFolderNotChosen => '(not chosen)';

  @override
  String get webReverseHarStart => 'Start';

  @override
  String get webReverseHarStop => 'Stop';

  @override
  String get webReverseHarNotes => 'Notes';

  @override
  String get webReverseHarClose => 'Close';

  @override
  String get webReverseHarLastFilePrefix => 'Last: ';

  @override
  String get webReverseHarNotesBody =>
      '· Save now: copy internal HAR draft to chosen .har path.\n· Load external HAR: parse HAR 1.2 and write back to networkRequests; merge optional.\n· Auto-rotate: writes current snapshot to folder with ISO-timestamped .har every N minutes; survives dialog close — stop manually.';

  @override
  String webReverseHarExportException(String error) {
    return 'Export error: $error';
  }

  @override
  String webReverseHarLoadException(String error) {
    return 'Load error: $error';
  }

  @override
  String webReverseHarLoadResult(int loaded, int skipped, String mode) {
    return 'Loaded: $loaded / skipped $skipped ($mode)';
  }

  @override
  String webReverseHarCapturedEntries(int count) {
    return 'Captured entries: $count';
  }

  @override
  String webReverseHarRunningInfo(int rotations, String remaining) {
    return 'Running · $rotations rotations · next in $remaining';
  }

  @override
  String get webReverseWaterfallTitle => 'Network Waterfall';

  @override
  String get webReverseWaterfallSubtitle =>
      'Blue = wait TTFB, Green = download; click row to copy URL';

  @override
  String get webReverseWaterfallRefresh => 'Refresh';

  @override
  String get webReverseWaterfallImportHar => 'Import HAR';

  @override
  String get webReverseWaterfallExportHar => 'Export HAR';

  @override
  String get webReverseWaterfallFilterHint => 'filter URL substring';

  @override
  String get webReverseWaterfallOnlyXhr => 'XHR/Fetch only';

  @override
  String get webReverseWaterfallSortTime => 'Time';

  @override
  String get webReverseWaterfallSortDuration => 'Duration';

  @override
  String get webReverseWaterfallSortSize => 'Size';

  @override
  String get webReverseWaterfallNoRequests => 'No requests';

  @override
  String get webReverseWaterfallHeaderRequest => 'Request';

  @override
  String get webReverseWaterfallUrlCopied => 'URL copied';

  @override
  String get webReverseWaterfallClose => 'Close';

  @override
  String get webReverseWaterfallNoInitiator => 'No initiator info';

  @override
  String get webReverseWaterfallInitiatorTitle => 'Request Initiator';

  @override
  String get webReverseWaterfallInitiatorTypeLabel => 'Type';

  @override
  String get webReverseWaterfallJumpToSources => 'Open in Sources';

  @override
  String get webReverseWaterfallNoJsStack =>
      'No JavaScript stack (typical for parser/preflight)';

  @override
  String get webReverseWaterfallLoadHarTitle => 'Load HAR';

  @override
  String get webReverseWaterfallCancel => 'Cancel';

  @override
  String get webReverseWaterfallMerge => 'Merge';

  @override
  String get webReverseWaterfallReplace => 'Replace';

  @override
  String get webReverseWaterfallHarParseFailed => 'HAR parse failed';

  @override
  String get webReverseWaterfallHarSaveFailed => 'HAR save failed or timed out';

  @override
  String webReverseWaterfallInitiatorTooltipWithUrl(String type, String url) {
    return 'Initiator: $type\n$url';
  }

  @override
  String webReverseWaterfallInitiatorTooltipNoUrl(String type) {
    return 'Initiator: $type';
  }

  @override
  String webReverseWaterfallLoadHarPrompt(int count) {
    return 'Network list has $count entries. Choose load mode:';
  }

  @override
  String webReverseWaterfallLoadMergedResult(int loaded, int skipped) {
    return 'Merged: $loaded; skipped $skipped';
  }

  @override
  String webReverseWaterfallLoadReplacedResult(int loaded, int skipped) {
    return 'Replaced: $loaded; skipped $skipped';
  }

  @override
  String webReverseWaterfallHarSavedTo(String path) {
    return 'HAR saved to $path';
  }

  @override
  String get webReverseCookieEditorTitle => 'Cookie Editor';

  @override
  String get webReverseCookieEditorSubtitle =>
      'Network.getCookies / setCookie / deleteCookies — full CRUD';

  @override
  String get webReverseCookieEditorRefresh => 'Refresh';

  @override
  String get webReverseCookieEditorCopyJson => 'Copy JSON';

  @override
  String get webReverseCookieEditorCopiedJson => 'JSON copied';

  @override
  String get webReverseCookieEditorFilterHint => 'Filter name / domain / value';

  @override
  String get webReverseCookieEditorNewBtn => 'New';

  @override
  String get webReverseCookieEditorEmptyCookies => 'No cookies';

  @override
  String get webReverseCookieEditorEdit => 'Edit';

  @override
  String get webReverseCookieEditorDelete => 'Delete';

  @override
  String get webReverseCookieEditorFetching => 'Fetching cookies...';

  @override
  String get webReverseCookieEditorDeleteFailed => 'Delete failed';

  @override
  String get webReverseCookieEditorWriteFailed => 'Write failed';

  @override
  String get webReverseCookieEditorSaved => 'Saved';

  @override
  String get webReverseCookieEditorNewCookie => 'New Cookie';

  @override
  String get webReverseCookieEditorFieldName => 'name *';

  @override
  String get webReverseCookieEditorFieldValue => 'value';

  @override
  String get webReverseCookieEditorFieldDomain => 'domain';

  @override
  String get webReverseCookieEditorFieldPath => 'path';

  @override
  String get webReverseCookieEditorFieldUrl => 'URL (optional)';

  @override
  String get webReverseCookieEditorFieldExpires => 'expires (unix sec)';

  @override
  String get webReverseCookieEditorSameSiteUnset => 'unset';

  @override
  String get webReverseCookieEditorCancel => 'Cancel';

  @override
  String get webReverseCookieEditorSave => 'Save';

  @override
  String get webReverseCookieEditorNameRequired => 'name required';

  @override
  String webReverseCookieEditorCookieCount(int count) {
    return '$count cookies';
  }

  @override
  String webReverseCookieEditorDeleted(String name) {
    return 'Deleted $name';
  }

  @override
  String webReverseCookieEditorEditCookie(String name) {
    return 'Edit $name';
  }

  @override
  String get webReverseInputSimTitle => 'Input Event Simulator';

  @override
  String get webReverseInputSimDispatchingClick => 'Dispatching click...';

  @override
  String get webReverseInputSimDispatched => 'Dispatched';

  @override
  String get webReverseInputSimDispatchingKey => 'Dispatching key...';

  @override
  String get webReverseInputSimKeyDispatched => 'Key dispatched';

  @override
  String get webReverseInputSimInsertingText => 'Inserting text...';

  @override
  String get webReverseInputSimInserted => 'Inserted';

  @override
  String get webReverseInputSimButton => 'Button';

  @override
  String get webReverseInputSimClickCount => 'Click count';

  @override
  String get webReverseInputSimModifiers => 'Modifiers';

  @override
  String get webReverseInputSimClickBtn => 'Click';

  @override
  String get webReverseInputSimWheelDown => 'Wheel ↓';

  @override
  String get webReverseInputSimWheelUp => 'Wheel ↑';

  @override
  String get webReverseInputSimKeyTextLabel => 'text (printable char)';

  @override
  String get webReverseInputSimDispatchKeyDownUp => 'Dispatch keyDown+keyUp';

  @override
  String get webReverseInputSimInsertTextLabel => 'insertText';

  @override
  String get webReverseInputSimInsertBtn => 'Insert';

  @override
  String get webReverseInputSimTabMouse => 'Mouse';

  @override
  String get webReverseInputSimTabKey => 'Key';

  @override
  String get webReverseInputSimTabText => 'Text';

  @override
  String get webReverseInputSimCloseBtn => 'Close';

  @override
  String webReverseInputSimClickedAt(String x, String y) {
    return 'Clicked ($x, $y)';
  }

  @override
  String webReverseInputSimWheelDy(String dy) {
    return 'Wheel dy=$dy';
  }

  @override
  String webReverseInputSimInsertedCount(int count) {
    return 'Inserted $count chars';
  }

  @override
  String get webReverseHeadlessBatchTitle => 'Headless batch capture';

  @override
  String get webReverseHeadlessBatchClose => 'Close';

  @override
  String get webReverseHeadlessBatchDesc =>
      'Open each URL in a background tab, then save network response index, console log and screenshot. Reuses the current browser process (cookies + hooks apply).';

  @override
  String get webReverseHeadlessBatchUrlsLabel => 'URL list (one per line)';

  @override
  String get webReverseHeadlessBatchOutputDirLabel => 'Output directory';

  @override
  String get webReverseHeadlessBatchNotSelected => '(not selected)';

  @override
  String get webReverseHeadlessBatchChoose => 'Choose';

  @override
  String get webReverseHeadlessBatchNetwork => 'Network';

  @override
  String get webReverseHeadlessBatchConsole => 'Console';

  @override
  String get webReverseHeadlessBatchScreenshot => 'Screenshot';

  @override
  String get webReverseHeadlessBatchStart => 'Start batch';

  @override
  String get webReverseHeadlessBatchStop => 'Stop';

  @override
  String get webReverseHeadlessBatchNoProgress => 'No progress yet';

  @override
  String get webReverseHeadlessBatchPickOutputDir => 'Pick output dir';

  @override
  String get webReverseHeadlessBatchNeedUrlAndDir =>
      'Need at least one http(s):// URL and an output directory';

  @override
  String get webReverseHeadlessBatchBrowserNotReady =>
      'Browser is not running yet — start a session first';

  @override
  String get webReverseHeadlessBatchPhaseStarting => 'Preparing';

  @override
  String get webReverseHeadlessBatchPhaseNavigating => 'Navigating';

  @override
  String get webReverseHeadlessBatchPhaseWaitingLoad => 'Waiting load';

  @override
  String get webReverseHeadlessBatchPhaseCapturingScreenshot =>
      'Capturing screenshot';

  @override
  String get webReverseHeadlessBatchPhaseDone => 'Done';

  @override
  String get webReverseHeadlessBatchPhaseFailed => 'Failed';

  @override
  String get webReverseHeadlessBatchPhaseCancelled => 'Cancelled';

  @override
  String webReverseHeadlessBatchFinished(int ok, int total) {
    return 'Batch finished: $ok/$total ok';
  }

  @override
  String webReverseHeadlessBatchEventCount(int events, int total) {
    return '$events / $total events';
  }

  @override
  String webReverseHeadlessBatchResultStats(int net, int log, String dir) {
    return '$net net · $log log · $dir';
  }

  @override
  String get webReverseResendRequestUrlEmpty => 'URL is required';

  @override
  String get webReverseResendRequestUrlInvalid => 'Invalid URL';

  @override
  String get webReverseResendRequestAborted => 'Aborted';

  @override
  String get webReverseResendRequestFooterNote =>
      'This dialog re-issues via Dart HttpClient (bypasses CSP/CORS).';

  @override
  String get webReverseResendRequestClose => 'Close';

  @override
  String get webReverseResendRequestAbort => 'Abort';

  @override
  String get webReverseResendRequestSend => 'Send';

  @override
  String get webReverseResendRequestTitle => 'Resend / Edit';

  @override
  String get webReverseResendRequestHeadersLabel => 'Headers';

  @override
  String get webReverseResendRequestAddRow => 'Add';

  @override
  String get webReverseResendRequestRemove => 'Remove';

  @override
  String get webReverseResendRequestBodyLabel => 'Body';

  @override
  String get webReverseResendRequestBeautifyJson => 'Beautify JSON';

  @override
  String get webReverseResendRequestInvalidJson => 'Body is not valid JSON';

  @override
  String get webReverseResendRequestExportAs => 'Export as:';

  @override
  String get webReverseResendRequestCopyResponse => 'Copy response';

  @override
  String get webReverseResendRequestResponseCopied => 'Response copied';

  @override
  String get webReverseResendRequestBase64Hint =>
      'Non-UTF8 response (base64 preview):';

  @override
  String get webReverseResendRequestBodyHint => 'Body:';

  @override
  String webReverseResendRequestCopiedAs(String kind) {
    return 'Copied as $kind';
  }

  @override
  String webReverseResendRequestHasNoBody(String method) {
    return '$method has no body';
  }

  @override
  String webReverseResendRequestHeadersWithCount(int count) {
    return 'Headers ($count)';
  }

  @override
  String get webReverseMockRulesTitle => 'Local Mock';

  @override
  String get webReverseMockRulesSubtitle =>
      'URL pattern match → Fetch.fulfillRequest returns a canned response';

  @override
  String get webReverseMockRulesExportJson => 'Export JSON';

  @override
  String get webReverseMockRulesImportJson => 'Import JSON';

  @override
  String get webReverseMockRulesListLabel => 'Rules';

  @override
  String get webReverseMockRulesAdd => 'Add';

  @override
  String get webReverseMockRulesEmptyRules => 'No rules';

  @override
  String get webReverseMockRulesDelete => 'Delete';

  @override
  String get webReverseMockRulesNewRule => 'New rule';

  @override
  String get webReverseMockRulesJsonCopied => 'JSON copied';

  @override
  String get webReverseMockRulesPickRule => 'Pick a rule on the left';

  @override
  String get webReverseMockRulesHits => 'Hits';

  @override
  String get webReverseMockRulesClear => 'Clear';

  @override
  String get webReverseMockRulesNoHits => 'No hits yet';

  @override
  String get webReverseMockRulesClose => 'Close';

  @override
  String get webReverseMockRulesSaveApply => 'Save & Apply';

  @override
  String get webReverseMockRulesRuleName => 'Name';

  @override
  String get webReverseMockRulesUrlPattern => 'URL pattern (* / ?)';

  @override
  String get webReverseMockRulesMethodLabel => 'Method (blank=ALL)';

  @override
  String get webReverseMockRulesExtraHeaders =>
      'Extra headers (Key: Value per line)';

  @override
  String get webReverseMockRulesResponseBody => 'Response body';

  @override
  String webReverseMockRulesSavedCount(int count) {
    return 'Saved $count rule(s)';
  }

  @override
  String webReverseMockRulesImportedCount(int count) {
    return 'Imported $count';
  }

  @override
  String webReverseMockRulesImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get webReverseStorageTitle => 'Storage Manager';

  @override
  String get webReverseStorageClose => 'Close';

  @override
  String get webReverseStorageCopied => 'Copied';

  @override
  String get webReverseStorageAddCookie => 'Add Cookie';

  @override
  String get webReverseStorageCancel => 'Cancel';

  @override
  String get webReverseStorageSave => 'Save';

  @override
  String get webReverseStorageCookieSaved => 'Cookie saved';

  @override
  String get webReverseStorageSaveFailed => 'Save failed';

  @override
  String get webReverseStorageAddEntry => 'Add entry';

  @override
  String get webReverseStorageEditEntry => 'Edit entry';

  @override
  String get webReverseStorageNoCookies => 'No cookies';

  @override
  String get webReverseStorageCopyJson => 'Copy JSON';

  @override
  String get webReverseStorageDelete => 'Delete';

  @override
  String get webReverseStorageAdd => 'Add';

  @override
  String get webReverseStorageEmpty => 'Empty';

  @override
  String get webReverseStorageNoDatabases => 'No databases';

  @override
  String get webReverseStoragePickDb => 'Pick DB';

  @override
  String get webReverseStoragePickStore => 'Pick store';

  @override
  String get webReverseStorageMoreRecords =>
      '… more records (showing first 50)';

  @override
  String get webReverseStorageRefresh => 'Refresh';

  @override
  String get webReverseCorsUrlRequired => 'URL required';

  @override
  String get webReverseCorsBadEval => 'Bad eval result';

  @override
  String get webReverseCorsMissing => 'missing';

  @override
  String get webReverseCorsMatchOrigin => 'matches current origin';

  @override
  String get webReverseCorsAllHeadersAllowed => 'all requested headers allowed';

  @override
  String get webReverseCorsCredsRule =>
      'must be true and Allow-Origin must not be *';

  @override
  String get webReverseCorsCacheSeconds => 'cache seconds';

  @override
  String get webReverseCorsResultCopied => 'Result copied';

  @override
  String get webReverseCorsTitle => 'CORS Preflight';

  @override
  String get webReverseCorsSubtitle =>
      'OPTIONS · diagnose Allow-Origin / Methods / Headers / Credentials';

  @override
  String get webReverseCorsCopyJson => 'Copy JSON';

  @override
  String get webReverseCorsTargetUrl => 'Target URL';

  @override
  String get webReverseCorsActualMethod => 'Actual Method';

  @override
  String get webReverseCorsOriginOverride =>
      'Origin override (optional, display only)';

  @override
  String get webReverseCorsCustomHeaders =>
      'Custom headers (one K: V per line; only names sent in preflight)';

  @override
  String get webReverseCorsRunButton => 'Run Preflight';

  @override
  String get webReverseCorsDiagnostics => 'Diagnostics';

  @override
  String get webReverseCorsAllHeaders => 'All response headers';

  @override
  String get webReverseCorsClose => 'Close';

  @override
  String webReverseCorsMustInclude(String method) {
    return 'must include $method';
  }

  @override
  String webReverseCorsMissingHeaders(String names) {
    return 'missing: $names';
  }

  @override
  String get webReverseCallgraphFetching => 'Fetching resources...';

  @override
  String get webReverseCallgraphFetchFailed => 'Fetch failed';

  @override
  String get webReverseCallgraphNoScripts => 'No JS scripts found';

  @override
  String get webReverseCallgraphTitle => 'JS Callgraph';

  @override
  String get webReverseCallgraphSubtitle =>
      'Heuristic regex parsing (noisy for minified bundles)';

  @override
  String get webReverseCallgraphScanBtn => 'Scan';

  @override
  String get webReverseCallgraphScriptLimit => 'Script limit';

  @override
  String get webReverseCallgraphPerScriptKb => 'Per script (KB)';

  @override
  String get webReverseCallgraphReverseHint => 'Reverse lookup: who calls …';

  @override
  String get webReverseCallgraphEmptyHint =>
      'Click Scan to parse current page JS';

  @override
  String get webReverseCallgraphFnsSuffix => 'fns';

  @override
  String get webReverseCallgraphPickScript => 'Pick a script';

  @override
  String get webReverseCallgraphClose => 'Close';

  @override
  String get webReverseCallgraphCopyGraph => 'Copy graph';

  @override
  String get webReverseCallgraphGraphCopied => 'Graph copied';

  @override
  String get webReverseCallgraphCalleesSuffix => 'callees';

  @override
  String get webReverseCallgraphNoDetectedCalls => '(no detected calls)';

  @override
  String webReverseCallgraphParsing(int done, int total, String url) {
    return 'Parsing $done/$total: $url';
  }

  @override
  String webReverseCallgraphDone(int scripts, int fns) {
    return 'Done: $scripts scripts, $fns functions';
  }

  @override
  String webReverseCallgraphScriptsCount(int count) {
    return 'Scripts ($count)';
  }

  @override
  String webReverseCallgraphHitsHeader(int count, String name) {
    return '$count hits calling \"$name\"';
  }

  @override
  String get webReverseSwDebugFetchingRegs => 'Fetching registrations...';

  @override
  String get webReverseSwDebugToggleFailed => 'Toggle failed';

  @override
  String get webReverseSwDebugForceUpdateOn => 'Force-update on';

  @override
  String get webReverseSwDebugForceUpdateOff => 'Force-update off';

  @override
  String get webReverseSwDebugTitle => 'Service Worker Debug';

  @override
  String get webReverseSwDebugSubtitle =>
      'ServiceWorker domain: start/stop/update/unregister/sync/push';

  @override
  String get webReverseSwDebugRefresh => 'Refresh';

  @override
  String get webReverseSwDebugForceUpdateLabel =>
      'Force update SW on every navigation';

  @override
  String get webReverseSwDebugEmptyList => 'No service workers';

  @override
  String get webReverseSwDebugPushDataLabel => 'push data (string)';

  @override
  String get webReverseSwDebugBtnStart => 'Start';

  @override
  String get webReverseSwDebugBtnStop => 'Stop';

  @override
  String get webReverseSwDebugBtnUpdate => 'Update';

  @override
  String get webReverseSwDebugBtnSync => 'Dispatch sync';

  @override
  String get webReverseSwDebugBtnPush => 'Deliver push';

  @override
  String get webReverseSwDebugBtnUnregister => 'Unregister';

  @override
  String webReverseSwDebugWorkersCount(int count) {
    return '$count Service Workers';
  }

  @override
  String webReverseSwDebugMethodFailed(String method, String err) {
    return '$method failed: $err';
  }

  @override
  String webReverseSwDebugMethodOk(String method) {
    return '$method ok';
  }

  @override
  String get webReverseSetupTargetUrl => 'Target URL *';

  @override
  String get webReverseSetupObjective => 'Objective *';

  @override
  String get webReverseSetupObjectiveHint =>
      'e.g. reverse the wallpaper download API into a curl script';

  @override
  String get webReverseSetupTriggerActions => 'Trigger actions (optional)';

  @override
  String get webReverseSetupTriggerHint =>
      'e.g. log in then click \"Download Original\"';

  @override
  String get webReverseSetupLoginMode => 'Login mode';

  @override
  String get webReverseSetupBrowser => 'Browser (detected)';

  @override
  String get webReverseSetupProxy => 'Proxy (optional)';

  @override
  String get webReverseSetupKeywords => 'Keywords (optional, comma-separated)';

  @override
  String get webReverseSetupCreateThread => 'Create Thread';

  @override
  String get webReverseSetupHeaderTitle => 'New Web Reverse Session';

  @override
  String get webReverseSetupHeaderSubtitle =>
      'Browser will dock to the right of the main window after start';

  @override
  String get webReverseSetupClose => 'Close';

  @override
  String get webReverseSetupProfileDir => 'User Data Dir';

  @override
  String get webReverseSetupLockDetected =>
      'Stale SingletonLock / lockfile detected — may block next launch.';

  @override
  String get webReverseSetupWorking => 'Working…';

  @override
  String webReverseSetupCooldown(int seconds) {
    return 'Cool-down ${seconds}s';
  }

  @override
  String get webReverseSetupResolveLock => 'Resolve profile lock';

  @override
  String get webReverseSignatureDiffHeaderTitle => 'Signature Field Locator';

  @override
  String get webReverseSignatureDiffHeaderSubtitle =>
      'Identify dynamic (sign / ts / nonce) vs stable fields across captures of the same endpoint';

  @override
  String get webReverseSignatureDiffRefresh => 'Refresh';

  @override
  String get webReverseSignatureDiffSearchHint => 'Search endpoint';

  @override
  String get webReverseSignatureDiffNoGroups =>
      'No analyzable groups (need ≥2 samples)';

  @override
  String get webReverseSignatureDiffEmptyHint =>
      'Hit the same API multiple times in Network panel, then return to analyze.';

  @override
  String get webReverseSignatureDiffCopyReport => 'Copy report';

  @override
  String get webReverseSignatureDiffStable => 'Stable';

  @override
  String get webReverseSignatureDiffDynamic => 'Dynamic';

  @override
  String get webReverseSignatureDiffIncreasing => 'Increasing';

  @override
  String get webReverseSignatureDiffFixedHash => 'Fixed-len hash';

  @override
  String get webReverseSignatureDiffSectionQuery => 'Query';

  @override
  String get webReverseSignatureDiffSectionHeaders => 'Headers';

  @override
  String get webReverseSignatureDiffSectionBody => 'Body fields';

  @override
  String get webReverseSignatureDiffReportTitle => 'Signature Diff';

  @override
  String get webReverseSignatureDiffReportSamples => 'samples';

  @override
  String get webReverseSignatureDiffReportCopied =>
      'Report copied to clipboard';

  @override
  String get webReverseCoverageStartFailed => 'start failed';

  @override
  String get webReverseCoverageCollecting => 'Collecting…';

  @override
  String get webReverseCoverageTakeFailed => 'take failed';

  @override
  String get webReverseCoverageStopped => 'Stopped';

  @override
  String get webReverseCoverageReportCopied => 'Report copied';

  @override
  String get webReverseCoverageTitle => 'JS Coverage';

  @override
  String get webReverseCoverageSubtitle =>
      'Start → exercise the page → take a sample to see which scripts ran';

  @override
  String get webReverseCoverageRecording => 'RECORDING';

  @override
  String get webReverseCoverageStart => 'Start';

  @override
  String get webReverseCoverageTake => 'Take';

  @override
  String get webReverseCoverageStop => 'Stop';

  @override
  String get webReverseCoverageFilterHint => 'Filter by URL';

  @override
  String get webReverseCoverageCopyReport => 'Copy report';

  @override
  String get webReverseCoverageNoData =>
      'No data. Start → use the page → Take.';

  @override
  String get webReverseCoverageClose => 'Close';

  @override
  String get webReverseCoverageCopyUrl => 'Copy URL';

  @override
  String get webReverseCoverageCopied => 'Copied';

  @override
  String webReverseCoverageSampledCount(int count) {
    return 'Sampled $count scripts';
  }

  @override
  String get webReverseDeviceEmuTitle => 'Device Emulation';

  @override
  String get webReverseDeviceEmuPresets => 'Presets';

  @override
  String get webReverseDeviceEmuCustom => 'Custom';

  @override
  String get webReverseDeviceEmuWidth => 'Width';

  @override
  String get webReverseDeviceEmuHeight => 'Height';

  @override
  String get webReverseDeviceEmuMobileMode => 'mobile';

  @override
  String get webReverseDeviceEmuUaHint => 'leave empty to keep default';

  @override
  String get webReverseDeviceEmuApplyCustom => 'Apply Custom';

  @override
  String get webReverseDeviceEmuReset => 'Reset';

  @override
  String get webReverseDeviceEmuClose => 'Close';

  @override
  String get webReverseDeviceEmuMinSize => 'min 100×100';

  @override
  String get webReverseDeviceEmuResetDone => 'Reset to default';

  @override
  String get webReverseDeviceEmuApplied => 'Applied';

  @override
  String get webReverseDeviceEmuClearingOverrides => 'Clearing overrides...';

  @override
  String get webReverseDeviceEmuApplyingCustom => 'Applying custom metrics...';

  @override
  String webReverseDeviceEmuApplyingPreset(String label) {
    return 'Applying $label...';
  }

  @override
  String webReverseDeviceEmuAppliedPreset(String label) {
    return 'Applied $label';
  }

  @override
  String webReverseDeviceEmuAppliedCustomSize(int w, int h, String dpr) {
    return 'Applied $w×$h @ ${dpr}x';
  }

  @override
  String get webReverseWatchCopiedJson => 'JSON copied';

  @override
  String get webReverseWatchTitle => 'Watch Expressions';

  @override
  String get webReverseWatchExportJson => 'Export JSON';

  @override
  String get webReverseWatchPause => 'Pause';

  @override
  String get webReverseWatchResume => 'Resume';

  @override
  String get webReverseWatchNoExpressions => 'No expressions';

  @override
  String get webReverseWatchAwaiting => 'awaiting…';

  @override
  String get webReverseWatchDelete => 'Delete';

  @override
  String get webReverseWatchNameLabel => 'Name (optional)';

  @override
  String get webReverseWatchExpressionLabel => 'JS expression';

  @override
  String get webReverseWatchAddWatch => 'Add watch';

  @override
  String get webReverseWatchPickWatch => 'Pick a watch';

  @override
  String get webReverseWatchClose => 'Close';

  @override
  String get webReverseWatchInterval => 'Interval';

  @override
  String get webReverseWatchNewestFirst => 'newest first';

  @override
  String get webReverseWatchAwaitingFirst => 'awaiting first eval…';

  @override
  String webReverseWatchSubtitleHint(int ms, int count) {
    return 'Polls Runtime.evaluate every ${ms}ms, keeps last $count samples';
  }

  @override
  String webReverseWatchHistory(int count) {
    return 'History ($count)';
  }

  @override
  String get webReverseAccountSnapTitle => 'Account Snapshots';

  @override
  String get webReverseAccountSnapSubtitle =>
      'Save cookies + localStorage/sessionStorage; one-click switch between accounts';

  @override
  String get webReverseAccountSnapNameLabel => 'Name for current account';

  @override
  String get webReverseAccountSnapNameHint => 'e.g. main / test-001';

  @override
  String get webReverseAccountSnapCapture => 'Capture';

  @override
  String get webReverseAccountSnapExportAll => 'Export all';

  @override
  String get webReverseAccountSnapImport => 'Import';

  @override
  String get webReverseAccountSnapClose => 'Close';

  @override
  String get webReverseAccountSnapEmptyHint =>
      'No snapshots yet. Type a name above → click \"Capture\".';

  @override
  String get webReverseAccountSnapApply => 'Apply';

  @override
  String get webReverseAccountSnapDelete => 'Delete';

  @override
  String get webReverseAccountSnapApplyFailedNoCdp =>
      'Apply failed: no CDP session';

  @override
  String get webReverseAccountSnapNotSnapshotJson =>
      'Clipboard is not a snapshot JSON';

  @override
  String webReverseAccountSnapSavedSnapshot(String name, int count) {
    return 'Saved \"$name\" ($count cookies)';
  }

  @override
  String webReverseAccountSnapAppliedSnapshot(String name) {
    return 'Applied \"$name\". Refresh the page so JS re-reads it.';
  }

  @override
  String webReverseAccountSnapCopiedCount(int count) {
    return 'Copied $count snapshots JSON to clipboard';
  }

  @override
  String webReverseAccountSnapImportedCount(int count) {
    return 'Imported $count snapshots';
  }

  @override
  String webReverseAccountSnapSnapshotsCount(int count) {
    return '$count total';
  }

  @override
  String get webReverseReqBpNewBreakpoint => 'New breakpoint';

  @override
  String get webReverseReqBpTitle => 'Request Breakpoints';

  @override
  String get webReverseReqBpSubtitle =>
      'Match by URL/body substring → log hit + optional JS eval. Toggle \"Intercept\" first.';

  @override
  String get webReverseReqBpInterceptOff => 'Intercept OFF';

  @override
  String get webReverseReqBpAdd => 'Add';

  @override
  String get webReverseReqBpEmptyHint => 'Click + to add your first breakpoint';

  @override
  String get webReverseReqBpUnnamed => '(unnamed)';

  @override
  String get webReverseReqBpPickHint => 'Pick a breakpoint to edit';

  @override
  String get webReverseReqBpClear => 'Clear';

  @override
  String get webReverseReqBpNoHits => 'No hits yet';

  @override
  String get webReverseReqBpNameField => 'Name';

  @override
  String get webReverseReqBpAnyMethod => 'Any';

  @override
  String get webReverseReqBpUrlContains => 'URL contains';

  @override
  String get webReverseReqBpBodyContains => 'Body contains';

  @override
  String get webReverseReqBpEvalOnHit => 'Eval on hit (optional)';

  @override
  String get webReverseReqBpEvalHint =>
      'e.g. debugger; or console.trace(\"hit\", new Error().stack)';

  @override
  String get webReverseReqBpDeleteBreakpoint => 'Delete breakpoint';

  @override
  String webReverseReqBpHitsCount(int count) {
    return 'Hits (recent $count)';
  }

  @override
  String get webReverseWsInjectTitle => 'WebSocket Inject';

  @override
  String get webReverseWsInjectSubtitle =>
      'All page-created WebSockets are proxied → pick one → inject any text frame';

  @override
  String get webReverseWsInjectProxyOn => 'PROXY ON';

  @override
  String get webReverseWsInjectInstallFailed => 'Install failed';

  @override
  String get webReverseWsInjectRefresh => 'Refresh';

  @override
  String get webReverseWsInjectNoLive =>
      'No live WebSockets.\nRefresh the page to let the proxy intercept new ones.';

  @override
  String get webReverseWsInjectPayloadLabel => 'Text frame / JSON';

  @override
  String get webReverseWsInjectPaste => 'Paste';

  @override
  String get webReverseWsInjectPickTarget => 'Pick a target';

  @override
  String get webReverseWsInjectTargetLabel => 'Target';

  @override
  String get webReverseWsInjectLogEmpty => 'Inject log appears here';

  @override
  String get webReverseWsInjectClose => 'Close';

  @override
  String get webReverseWsInjectSend => 'Send';

  @override
  String get webReverseWsInjectInjected => 'Injected';

  @override
  String get webReverseWsInjectInjectFailed => 'Inject failed';

  @override
  String webReverseWsInjectLiveCount(int count) {
    return '$count live WebSocket(s)';
  }

  @override
  String webReverseWsInjectSentBytes(int count) {
    return 'Sent $count bytes';
  }

  @override
  String webReverseWsInjectFailedReason(String reason) {
    return 'Failed: $reason';
  }

  @override
  String get webReversePmTitle => 'postMessage Trace';

  @override
  String get webReversePmSubtitle =>
      'Inject hook → ring buffer → drain every 800ms (incl. iframe)';

  @override
  String get webReversePmHookInjected => 'Hook injected';

  @override
  String get webReversePmHookStopped => 'Stopped (full unhook after reload)';

  @override
  String get webReversePmStop => 'Stop';

  @override
  String get webReversePmInject => 'Inject';

  @override
  String get webReversePmClear => 'Clear';

  @override
  String get webReversePmCopyJson => 'Copy JSON';

  @override
  String get webReversePmFilterHint => 'filter by substring';

  @override
  String get webReversePmChipSend => 'Send';

  @override
  String get webReversePmChipRecv => 'Recv';

  @override
  String get webReversePmWaiting => 'Waiting for postMessage…';

  @override
  String get webReversePmClickToCapture => 'Click Inject to start capturing';

  @override
  String get webReversePmTagSend => 'SEND';

  @override
  String get webReversePmTagRecv => 'RECV';

  @override
  String get webReversePmClose => 'Close';

  @override
  String webReversePmCopiedCount(int count) {
    return 'Copied $count records';
  }

  @override
  String get webReverseThrottleEnableNetwork => 'Enable Network domain...';

  @override
  String get webReverseThrottleApplyFailed => 'Apply failed';

  @override
  String get webReverseThrottleConditionsApplied =>
      'Network conditions applied';

  @override
  String get webReverseThrottleTitle => 'Network Throttling';

  @override
  String get webReverseThrottleSubtitle =>
      'Network.emulateNetworkConditions: presets or custom kbps/latency';

  @override
  String get webReverseThrottlePresets => 'Presets';

  @override
  String get webReverseThrottleCustom => 'Custom';

  @override
  String get webReverseThrottleDownKbps => 'Down kbps (0=∞)';

  @override
  String get webReverseThrottleUpKbps => 'Up kbps (0=∞)';

  @override
  String get webReverseThrottleLatencyMs => 'Latency ms';

  @override
  String get webReverseThrottleOffline => 'Offline';

  @override
  String get webReverseThrottleDisableCache => 'Disable cache';

  @override
  String get webReverseThrottleApplyCustom => 'Apply custom';

  @override
  String get webReverseThrottleReset => 'Reset (no throttle)';

  @override
  String get webReverseThrottleNotes => 'Notes';

  @override
  String get webReverseThrottleNotesBody =>
      '· Throttle applies to the entire session of current target; reset or close to restore.\n· kbps is converted to bytes/s via *1024/8 before sending; offline ignores throughput.\n· Cache disable applies to both Fetch & Disk Cache, useful for cold-load reproduction.';

  @override
  String get webReverseThrottleClose => 'Close';

  @override
  String get webReverseThrottleUnknownError => 'unknown';

  @override
  String webReverseThrottleStatusFailed(String reason) {
    return 'Failed: $reason';
  }

  @override
  String webReverseThrottleStatusApplied(String summary) {
    return 'Applied: $summary';
  }

  @override
  String get webReverseDomMutTitle => 'DOM Mutation Recorder';

  @override
  String get webReverseDomMutSubtitle =>
      'Injects MutationObserver → live timeline';

  @override
  String get webReverseDomMutRecordingStarted => 'Recording DOM mutations';

  @override
  String webReverseDomMutInstallFailed(String error) {
    return 'Install failed: $error';
  }

  @override
  String webReverseDomMutCopiedRecords(int count) {
    return 'Copied $count records';
  }

  @override
  String get webReverseDomMutExportJson => 'Export JSON';

  @override
  String get webReverseDomMutRecording => 'Recording';

  @override
  String get webReverseDomMutStart => 'Start';

  @override
  String get webReverseDomMutStop => 'Stop';

  @override
  String get webReverseDomMutClear => 'Clear';

  @override
  String get webReverseDomMutFilterHint => 'Filter (substring)';

  @override
  String get webReverseDomMutAutoFollow => 'Auto-follow';

  @override
  String webReverseDomMutCounter(int count, int total) {
    return '$count / $total';
  }

  @override
  String get webReverseDomMutWaiting => 'Waiting for mutations…';

  @override
  String get webReverseDomMutPressStart => 'Press Start';

  @override
  String get webReverseDomMutClose => 'Close';

  @override
  String get webReverseSmTitle => 'SourceMap Resolver';

  @override
  String get webReverseSmSubtitle =>
      'min file:line:col → original source:line:col';

  @override
  String get webReverseSmInvalidInput => 'invalid input';

  @override
  String get webReverseSmFetching => 'Fetching sourcemap...';

  @override
  String webReverseSmFetchFailed(String error) {
    return 'Fetch failed: $error';
  }

  @override
  String get webReverseSmBadEvalResult => 'Bad eval result';

  @override
  String get webReverseSmNoMapping => 'No mapping segment';

  @override
  String get webReverseSmResolved => 'Resolved';

  @override
  String get webReverseSmCopied => 'Copied';

  @override
  String get webReverseSmUrlLabel => 'Minified file URL';

  @override
  String get webReverseSmLineLabel => 'Line (1-based)';

  @override
  String get webReverseSmColLabel => 'Column (0-based)';

  @override
  String get webReverseSmResolve => 'Resolve';

  @override
  String get webReverseSmEmptyHint => 'Enter URL + position, then resolve';

  @override
  String get webReverseSmCopyTooltip => 'Copy';

  @override
  String get webReverseSmNameLabel => 'name';

  @override
  String get webReverseSmClose => 'Close';

  @override
  String get webReverseCssCovStarting => 'Enabling CSS & starting...';

  @override
  String webReverseCssCovStartFailed(String error) {
    return 'Start failed: $error';
  }

  @override
  String get webReverseCssCovTrackingActive =>
      'Tracking — interact with the page, then click \"Stop & Tally\".';

  @override
  String get webReverseCssCovStopping => 'Stopping and aggregating...';

  @override
  String webReverseCssCovStopFailed(String error) {
    return 'Stop failed: $error';
  }

  @override
  String webReverseCssCovResultsTallied(int sheets, int rules) {
    return '$sheets sheets, $rules rules total.';
  }

  @override
  String get webReverseCssCovJsonCopied => 'JSON copied';

  @override
  String get webReverseCssCovTitle => 'CSS Rule Coverage';

  @override
  String get webReverseCssCovSubtitle =>
      'CSS.startRuleUsageTracking · find dead rules';

  @override
  String get webReverseCssCovCopyJson => 'Copy JSON';

  @override
  String get webReverseCssCovTracking => 'Tracking';

  @override
  String get webReverseCssCovIdle => 'Idle';

  @override
  String get webReverseCssCovStopAndTally => 'Stop & Tally';

  @override
  String get webReverseCssCovStartTracking => 'Start Tracking';

  @override
  String get webReverseCssCovEmpty =>
      'No results yet. Start tracking then interact.';

  @override
  String webReverseCssCovRuleStats(
    int used,
    int total,
    String usedKb,
    String totalKb,
  ) {
    return '$used/$total rules · $usedKb/$totalKb KB';
  }

  @override
  String get webReverseCssCovClose => 'Close';

  @override
  String get webReverseAiCryptoStatusFetchResources => 'Fetching resources...';

  @override
  String get webReverseAiCryptoStatusDetecting => 'Detecting suspects...';

  @override
  String get webReverseAiCryptoStatusDone => 'Done';

  @override
  String get webReverseAiCryptoCopied => 'Copied to clipboard';

  @override
  String get webReverseAiCryptoTitle => 'AI Crypto Param Recover';

  @override
  String get webReverseAiCryptoSubtitle =>
      'Group endpoint → diff vars → locate in JS → copy prompt';

  @override
  String get webReverseAiCryptoRefresh => 'Refresh';

  @override
  String get webReverseAiCryptoEmpty =>
      'No analyzable endpoint (need ≥2 hits per endpoint)';

  @override
  String get webReverseAiCryptoAnalyze => 'Analyze';

  @override
  String get webReverseAiCryptoCopyPrompt => 'Copy prompt';

  @override
  String get webReverseAiCryptoSuspectsLabel => 'Suspects:';

  @override
  String get webReverseAiCryptoPromptHint =>
      'Click Analyze to generate the prompt.';

  @override
  String get webReverseAiCryptoClose => 'Close';

  @override
  String webReverseAiCryptoStatusSearchProgress(int done, int total) {
    return 'Search $done/$total';
  }

  @override
  String webReverseAiCryptoHits(int count) {
    return '$count hits';
  }

  @override
  String get webReverseCdpSendFailed => 'Send failed';

  @override
  String get webReverseCdpCopied => 'Copied';

  @override
  String get webReverseCdpTitle => 'CDP Raw Console';

  @override
  String get webReverseCdpMethodLabel => 'method';

  @override
  String get webReverseCdpUseSession => 'use page session';

  @override
  String get webReverseCdpSend => 'Send';

  @override
  String get webReverseCdpNoHistory => 'No history';

  @override
  String get webReverseCdpSendHint => 'Send a command';

  @override
  String get webReverseCdpClose => 'Close';

  @override
  String get webReverseCdpCopyResponse => 'Copy response';

  @override
  String get webReverseCdpParams => 'Params';

  @override
  String get webReverseCdpResponse => 'Response';

  @override
  String get webReverseCdpError => 'Error';

  @override
  String webReverseCdpInvalidJson(String error) {
    return 'Invalid JSON: $error';
  }

  @override
  String webReverseCdpSubtitle(int count) {
    return '⌘/Ctrl+Enter send · Ctrl+↑/↓ history · $count entries';
  }

  @override
  String get webReversePerfTitle => 'Performance Trace';

  @override
  String get webReversePerfSubtitle => 'Tracing → chrome-trace JSON';

  @override
  String get webReversePerfDuration => 'Duration';

  @override
  String get webReversePerfCategories => 'Trace Categories';

  @override
  String get webReversePerfCopyPath => 'Copy path';

  @override
  String get webReversePerfStop => 'Stop';

  @override
  String get webReversePerfStart => 'Start';

  @override
  String get webReversePerfClose => 'Close';

  @override
  String get webReversePerfTraceFailed => 'Trace failed or empty';

  @override
  String get webReversePerfStopping => 'Stopping, finalizing…';

  @override
  String get webReversePerfTraceSaved => 'Trace saved';

  @override
  String get webReversePerfPathCopied => 'Path copied';

  @override
  String webReversePerfRecording(int seconds) {
    return 'Recording (${seconds}s left)';
  }

  @override
  String webReversePerfSaved(String path, String kb) {
    return 'Saved: $path ($kb KB)';
  }

  @override
  String get webReverseReplayJsonCopied => 'JSON copied';

  @override
  String get webReverseReplayTitle => 'Network Request Replayer';

  @override
  String get webReverseReplaySubtitle =>
      'multi-select → sequential replay → diff';

  @override
  String get webReverseReplayCopyResultsJson => 'Copy results JSON';

  @override
  String get webReverseReplayFilterByUrl => 'Filter by URL';

  @override
  String get webReverseReplaySelectAll => 'Select All';

  @override
  String get webReverseReplayClear => 'Clear';

  @override
  String get webReverseReplayEmpty => 'No HTTP requests in session';

  @override
  String get webReverseReplayRunBatch => 'Run Batch';

  @override
  String get webReverseReplayClose => 'Close';

  @override
  String webReverseReplayDone(int ok, int total) {
    return 'Replay done: $ok/$total ok';
  }

  @override
  String webReverseReplayProgress(int done, int total) {
    return 'Replaying $done / $total';
  }

  @override
  String webReverseReplaySelected(int count, int total) {
    return 'Selected $count / $total';
  }

  @override
  String get webReverseGeoOverridesApplied => 'Overrides applied';

  @override
  String get webReverseGeoEnvOverridesApplied =>
      'Environment overrides applied';

  @override
  String get webReverseGeoOverridesCleared => 'Overrides cleared';

  @override
  String get webReverseGeoEnvOverridesCleared =>
      'Cleared environment overrides';

  @override
  String get webReverseGeoTitle => 'Geo / TZ / Locale Override';

  @override
  String get webReverseGeoCityPresets => 'City Presets';

  @override
  String get webReverseGeoEnableGeo => 'Enable geolocation override';

  @override
  String get webReverseGeoEnableTz => 'Enable timezone override';

  @override
  String get webReverseGeoEnableLocale => 'Enable locale override';

  @override
  String get webReverseGeoTip =>
      'Tip: overrides apply immediately within current target and persist across reloads. Inspect via navigator.geolocation, Intl.DateTimeFormat().resolvedOptions().timeZone, navigator.language. Hard-reload after override if a site caches detection.';

  @override
  String get webReverseGeoClear => 'Clear';

  @override
  String get webReverseGeoWorking => 'Working…';

  @override
  String get webReverseGeoApply => 'Apply Overrides';

  @override
  String get webReverseCollectionExportNothing => 'Nothing to export';

  @override
  String get webReverseCollectionExportTitle => 'Export Collection';

  @override
  String get webReverseCollectionExportSubtitle =>
      'Postman / Insomnia / Bruno / cURL / HAR — copy to clipboard';

  @override
  String get webReverseCollectionExportName => 'Collection name';

  @override
  String get webReverseCollectionExportUrlFilter => 'URL filter';

  @override
  String get webReverseCollectionExportXhrOnly => 'XHR/Fetch only';

  @override
  String get webReverseCollectionExportPreview2 => 'Preview: first 2 entries';

  @override
  String get webReverseCollectionExportClose => 'Close';

  @override
  String get webReverseCollectionExportCopyAction => 'Copy collection';

  @override
  String get webReverseCollectionExportNoMatch =>
      '// No matching requests.\n// Adjust the filter or turn off \"XHR/Fetch only\".';

  @override
  String webReverseCollectionExportCopied(int count) {
    return 'Copied $count requests to clipboard';
  }

  @override
  String webReverseCollectionExportMatchCount(int match, int total) {
    return '$match match · $total total';
  }

  @override
  String get webReverseJwtTitle => 'JWT Auto Refresh';

  @override
  String get webReverseJwtSubtitle =>
      'Scan JWTs in cookies/storage, run refresh JS when near exp';

  @override
  String get webReverseJwtScanNow => 'Scan now';

  @override
  String get webReverseJwtRefreshNow => 'Refresh now';

  @override
  String get webReverseJwtAuto => 'Auto';

  @override
  String get webReverseJwtIntervalSec => 'Interval(s)';

  @override
  String get webReverseJwtThresholdSec => 'Threshold(s)';

  @override
  String get webReverseJwtRefreshExpr => 'Refresh expression (async JS)';

  @override
  String get webReverseJwtNoneFound => 'No JWT found';

  @override
  String get webReverseJwtRefreshLog => 'Refresh log';

  @override
  String get webReverseJwtClose => 'Close';

  @override
  String webReverseJwtFoundCount(int count) {
    return 'JWTs ($count)';
  }

  @override
  String get webReverseWebauthnTitle => 'WebAuthn Virtual Authenticator';

  @override
  String get webReverseWebauthnDisabledBody =>
      'Toggle WebAuthn on to enable virtual authenticators. navigator.credentials.create/get will succeed without physical hardware.';

  @override
  String get webReverseWebauthnAdd => 'Add Virtual Authenticator';

  @override
  String get webReverseWebauthnAddBtn => 'Add';

  @override
  String get webReverseWebauthnNone => 'No authenticators yet';

  @override
  String get webReverseWebauthnClose => 'Close';

  @override
  String get webReverseWebauthnRefreshCreds => 'Refresh credentials';

  @override
  String get webReverseWebauthnRemove => 'Remove';

  @override
  String get webReverseWebauthnUserVerified => 'User verified';

  @override
  String webReverseWebauthnAdded(String id) {
    return 'Added $id';
  }

  @override
  String webReverseWebauthnCreatedCount(int count) {
    return 'Authenticators ($count)';
  }

  @override
  String webReverseWebauthnCredentialsCount(int count) {
    return 'Credentials ($count)';
  }

  @override
  String get webReverseInstallTitle => 'Google Chrome required';

  @override
  String get webReverseInstallClose => 'Close';

  @override
  String get webReverseInstallBody =>
      'The Web Reverse Expert relies on an external Chromium-based browser (Chrome / Edge / Brave / Chromium) driven via CDP. None was detected.';

  @override
  String get webReverseInstallOpen => 'Open';

  @override
  String get webReverseInstallHint =>
      'Install Chrome and retry. If Edge / Brave / Chromium is already installed, click \"I have installed, recheck\".';

  @override
  String get webReverseInstallInstalled => 'I Have Installed';

  @override
  String get webReverseProfileEmptyPath => 'Empty profile path; nothing done';

  @override
  String get webReverseProfileNoResidual =>
      'No residual locks. If launch still fails, see other causes in diagnosis.';

  @override
  String get webReverseProfileResetTitle =>
      'Locks still present — reset profile?';

  @override
  String get webReverseProfileResetConfirm => 'Reset now';

  @override
  String get webReverseProfileKept =>
      'Profile kept; locks may still block next launch.';

  @override
  String webReverseProfileCleanFailed(String error) {
    return 'Clean failed: $error';
  }

  @override
  String webReverseProfileCleaned(int count) {
    return 'Cleared $count lock file(s); profile is healthy';
  }

  @override
  String webReverseProfileResetBody(String path) {
    return 'Cleaned SingletonLock residues but locks still exist.\n\nProceeding will recursively delete:\n$path\n\nCookies / Login Data / extensions / history under this profile will be lost; a fresh profile is rebuilt on next launch.';
  }

  @override
  String webReverseProfileResetDone(String path) {
    return 'Profile reset: $path (60s cool-down)';
  }

  @override
  String webReverseProfileResetFailed(String error) {
    return 'Reset failed: $error';
  }

  @override
  String get webReverseReplNoResult => '(no result)';

  @override
  String get webReverseReplCopied => 'Copied';

  @override
  String get webReverseReplTitle => 'Console REPL';

  @override
  String get webReverseReplSubtitle =>
      'Runtime.evaluate · ↑/↓ history · Ctrl/⌘+Enter run';

  @override
  String get webReverseReplClear => 'Clear log';

  @override
  String get webReverseReplEmpty => 'Type JS below → Ctrl/⌘+Enter to run';

  @override
  String get webReverseReplHint =>
      'eg: document.title or await fetch(\"/api\").then(r=>r.json())';

  @override
  String get webReverseReplRun => 'Run';

  @override
  String get webReverseConsoleEvalFailed => 'Eval failed';

  @override
  String get webReverseConsoleEmpty => 'No console output yet.';

  @override
  String get webReverseConsolePausedHint =>
      'Debugger paused · expressions evaluate in the top frame scope';

  @override
  String get webReverseConsoleReplHint => 'JS expression; ↑↓ history';

  @override
  String get webReverseConsoleClusterCopied => 'Cluster JSON copied';

  @override
  String get webReverseConsoleClusterTitle => 'Console Clusters';

  @override
  String get webReverseConsoleClusterRefresh => 'Refresh';

  @override
  String get webReverseConsoleClusterFilterHint => 'filter';

  @override
  String get webReverseConsoleClusterNoMatch => 'No matching entries';

  @override
  String get webReverseConsoleClusterCopyJson => 'Copy JSON';

  @override
  String webReverseConsoleClusterSubtitle(int entries, int clusters) {
    return 'dedupe by level + normalized first line · $entries entries / $clusters clusters';
  }

  @override
  String webReverseConsoleClusterTimes(String first, String last) {
    return 'first: $first\nlast: $last';
  }

  @override
  String webReverseConsoleClusterMore(int count) {
    return '… and $count more';
  }

  @override
  String get webReverseDomSearchTitle => 'DOM Selector Search';

  @override
  String get webReverseDomSearchSearching => 'Searching...';

  @override
  String get webReverseDomSearchNoMatches => 'No matches';

  @override
  String get webReverseDomSearchHint => 'selector / text / XPath, Enter to run';

  @override
  String get webReverseDomSearchRun => 'Run';

  @override
  String get webReverseDomSearchExample =>
      'e.g. button[data-action] · #login · //a[contains(@href,\"docs\")]';

  @override
  String get webReverseDomSearchHighlight => 'Highlight in page';

  @override
  String webReverseDomSearchFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String webReverseDomSearchGetFailed(String error) {
    return 'getSearchResults failed: $error';
  }

  @override
  String webReverseDomSearchHitCount(int total, int shown) {
    return 'Matched $total, showing top $shown';
  }

  @override
  String get webReverseFrameTreeTitle => 'Frame Tree';

  @override
  String get webReverseFrameTreeSubtitle =>
      'Page.getFrameTree · main + nested iframes';

  @override
  String get webReverseFrameTreeRefresh => 'Refresh';

  @override
  String get webReverseFrameTreeCopyJson => 'Copy JSON';

  @override
  String get webReverseFrameTreeCopied => 'Copied';

  @override
  String get webReverseFrameTreeEmpty => 'No frames';

  @override
  String webReverseFrameTreeFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String webReverseFrameTreeCount(int count) {
    return '$count frames';
  }

  @override
  String get webReverseCpuThrottleOff => 'CPU throttle off';

  @override
  String get webReverseCpuThrottleResetDone => 'Reset';

  @override
  String get webReverseCpuThrottleTitle => 'CPU Throttling';

  @override
  String get webReverseCpuThrottlePresets => 'Presets';

  @override
  String get webReverseCpuThrottleNote =>
      'Throttling stays active after dialog closes. Pick 1× (off) or Reset to clear.';

  @override
  String get webReverseCpuThrottleReset => 'Reset (1×)';

  @override
  String webReverseCpuThrottleApplying(String rate) {
    return 'Throttling $rate×...';
  }

  @override
  String webReverseCpuThrottleFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String webReverseCpuThrottleCurrent(String rate) {
    return 'CPU throttled $rate×';
  }

  @override
  String webReverseCpuThrottleSliderLabel(String rate) {
    return 'Slider $rate×';
  }

  @override
  String webReverseCpuThrottleApplied(String rate) {
    return 'Applied $rate× throttle';
  }

  @override
  String get webReverseHeapTaking => 'Taking heap snapshot...';

  @override
  String get webReverseHeapFailed => 'Snapshot failed or empty';

  @override
  String get webReverseHeapSavedToast => 'Snapshot saved';

  @override
  String get webReverseHeapPathCopied => 'Path copied';

  @override
  String get webReverseHeapSubtitle =>
      'HeapProfiler.takeHeapSnapshot → .heapsnapshot';

  @override
  String get webReverseHeapEmptyHint =>
      'Click below to capture current page V8 heap snapshot.\nLarge pages may produce 50MB+ files.';

  @override
  String get webReverseHeapCopyPath => 'Copy path';

  @override
  String get webReverseHeapTake => 'Take Snapshot';

  @override
  String webReverseHeapSaved(String path, String mb) {
    return 'Saved: $path ($mb MB)';
  }

  @override
  String get webReverseRealtimeDirSent => 'Sent';

  @override
  String get webReverseRealtimeDirRecv => 'Recv';

  @override
  String get webReverseRealtimeDirError => 'Error';

  @override
  String get webReverseRealtimePayloadCopied => 'Payload copied';

  @override
  String get webReverseRealtimeTitle => 'Realtime';

  @override
  String get webReverseRealtimeEmpty => 'No WebSocket / EventSource yet.';

  @override
  String get webReverseRealtimePickPrompt =>
      'Pick a connection to view frames.';

  @override
  String get webReverseRealtimeFilterHint => 'Filter payload (substring)';

  @override
  String get webReverseRealtimeAutoFollow => 'Auto-follow';

  @override
  String get webReverseRealtimeNoMatching => 'No matching frames.';

  @override
  String webReverseRealtimeFrameCount(int count) {
    return '$count frames';
  }

  @override
  String get webReverseMarkupTitle => 'Screenshot Markup';

  @override
  String get webReverseMarkupSaveWithout => 'Save without markup';

  @override
  String get webReverseMarkupExporting => 'Exporting…';

  @override
  String get webReverseMarkupDone => 'Done';

  @override
  String get webReverseMarkupUndo => 'Undo';

  @override
  String get webReverseMarkupClear => 'Clear';

  @override
  String get webReverseMarkupAddTextTitle => 'Add text label';

  @override
  String get webReverseMarkupLabelHint => 'Label';

  @override
  String get webReverseMarkupAdd => 'Add';

  @override
  String get webReverseElementsLoadFailed =>
      'Load failed: browser not running or CDP unavailable';

  @override
  String get webReverseElementsSelectorFailed => 'Failed to build selector';

  @override
  String get webReverseElementsSelectorCopied => 'Selector copied';

  @override
  String get webReverseElementsXPathFailed => 'Failed to build XPath';

  @override
  String get webReverseElementsXPathCopied => 'XPath copied';

  @override
  String get webReverseElementsReloadDom => 'Reload DOM root';

  @override
  String get webReverseElementsCopySelector => 'Copy selector';

  @override
  String get webReverseElementsCopyXPath => 'Copy XPath';

  @override
  String get webReverseElementsScrollIntoView => 'Scroll into view';

  @override
  String get webReverseElementsPickElement => 'Pick an element from the tree';

  @override
  String get webReverseElementsNoAttrs => 'No attributes';

  @override
  String get webReverseElementsNoComputed => 'No computed style';

  @override
  String get webReverseElementsNoListeners => 'No event listeners';

  @override
  String webReverseElementsAttrsTab(int count) {
    return 'Attrs ($count)';
  }

  @override
  String webReverseElementsComputedTab(int count) {
    return 'Computed ($count)';
  }

  @override
  String webReverseElementsListenersTab(int count) {
    return 'Listeners ($count)';
  }

  @override
  String get webReverseCryptoSecEncode => 'Encode';

  @override
  String get webReverseCryptoSecHash => 'Hash';

  @override
  String get webReverseCryptoSecTime => 'Time';

  @override
  String get webReverseCryptoClear => 'Clear';

  @override
  String get webReverseCryptoInputHint => 'Paste here…';

  @override
  String get webReverseCryptoInputLabel => 'Input';

  @override
  String get webReverseCryptoCopy => 'Copy';

  @override
  String get webReverseCryptoUseAsInput => 'Use as input';

  @override
  String get webReverseCryptoLengthLabel => 'Length';

  @override
  String get webReverseCryptoTsToIso => 'Timestamp → ISO';

  @override
  String get webReverseCryptoIsoToTs => 'ISO → Timestamp';

  @override
  String get webReverseCryptoNow => 'Now';

  @override
  String get webReverseCryptoUuidHint => 'Random UUID v4 (tap to copy)';

  @override
  String get webReverseCryptoRegenerate => 'Regenerate';

  @override
  String webReverseCryptoCopied(String label) {
    return '$label copied';
  }

  @override
  String webReverseCryptoLengthValue(int chars, int bytes) {
    return 'chars $chars / bytes $bytes';
  }

  @override
  String get webReverseHooksDefaultCode =>
      'Runs before every document load; patch window/fetch etc.';

  @override
  String get webReverseHooksSavedToast => 'Saved and reloaded';

  @override
  String get webReverseHooksDeleteTitle => 'Delete hook?';

  @override
  String get webReverseHooksDeleteContent => 'Will be uninstalled immediately.';

  @override
  String get webReverseHooksDelete => 'Delete';

  @override
  String get webReverseHooksDiscardTitle => 'Discard unsaved changes?';

  @override
  String get webReverseHooksKeepEditing => 'Keep editing';

  @override
  String get webReverseHooksDiscardConfirm => 'Discard';

  @override
  String get webReverseHooksLibrary => 'Hook library';

  @override
  String get webReverseHooksNew => 'New hook';

  @override
  String get webReverseHooksEmpty => 'No hooks yet.\nTap + to create one.';

  @override
  String get webReverseHooksPickPrompt => 'Pick a hook or create one.';

  @override
  String get webReverseHooksNameLabel => 'Name';

  @override
  String get webReverseHooksSave => 'Save (⌘S)';

  @override
  String get webReverseHooksSaved => 'Saved';

  @override
  String get webReverseHooksInfo =>
      'Save reloads instantly. Runs before each document loads; survives tab switch and reload.';

  @override
  String webReverseHooksNewName(String time) {
    return 'hook $time';
  }

  @override
  String get webReverseSnippetsDefaultCode =>
      'Write JS here. Runs in page context.';

  @override
  String get webReverseSnippetsNoResult => '(no result)';

  @override
  String get webReverseSnippetsDeleteTitle => 'Delete snippet?';

  @override
  String get webReverseSnippetsDeleteContent => 'This cannot be undone.';

  @override
  String get webReverseSnippetsDelete => 'Delete';

  @override
  String get webReverseSnippetsTitle => 'Snippet pad';

  @override
  String get webReverseSnippetsNew => 'New snippet';

  @override
  String get webReverseSnippetsEmpty =>
      'No snippets yet.\nTap + to create one.';

  @override
  String get webReverseSnippetsPickPrompt => 'Pick a snippet or create one.';

  @override
  String get webReverseSnippetsRun => 'Run (⌘R)';

  @override
  String get webReverseSnippetsSaveDirty => 'Save *';

  @override
  String webReverseSnippetsNewName(String time) {
    return 'snippet $time';
  }

  @override
  String get servicesTitle => 'Services';

  @override
  String get servicesSubtitle =>
      'Access professional services built by OpenHand for stable, controlled, and auditable execution.';

  @override
  String get servicesProprietaryBadge => 'Built by OpenHand';

  @override
  String get servicesAiInfrastructureExposureScanTitle =>
      'AI Infrastructure Exposure Scan';

  @override
  String get servicesAiInfrastructureExposureScanDescription =>
      'Discovers exposed AI services within authorized scope, identifies leaked credentials and risky configurations, and preserves auditable remediation evidence.';

  @override
  String get agentsTitle => 'Agents';

  @override
  String get agentsSubtitle =>
      'Manage Hermes Agent digital employees, permissions, tasks, clusters, audits, and KPIs.';

  @override
  String get agentsCreateAgent => 'Create agent';

  @override
  String get agentsEditAgent => 'Edit agent';

  @override
  String get agentsLoadFailed => 'Failed to load agents';

  @override
  String get agentsRetry => 'Retry';

  @override
  String get agentsEmptyTitle => 'No agents yet';

  @override
  String get agentsEmptyBody =>
      'Use Create to configure the first digital employee with scope, permissions, task desk, and governance.';

  @override
  String get agentsMentorLabel => 'Mentor';

  @override
  String get agentsStopAgent => 'Stop agent';

  @override
  String get agentsStartAgent => 'Start agent';

  @override
  String get agentsActivities => 'Activities';

  @override
  String get agentsLogs => 'Logs';

  @override
  String get agentsCapabilityLogs => 'Capability logs';

  @override
  String get agentsApprovals => 'Approvals';

  @override
  String get agentsCluster => 'Cluster';

  @override
  String get agentsMore => 'More';

  @override
  String get agentsTaskDesk => 'Task desk';

  @override
  String get agentsAuditReport => 'Audit report';

  @override
  String get agentsKpi => 'KPI';

  @override
  String get agentsResources => 'Resources';

  @override
  String get agentsDeleteAgent => 'Delete agent';

  @override
  String agentsTasksCount(int running, int total) {
    return 'Tasks $running/$total';
  }

  @override
  String agentsApprovalsCount(int count) {
    return 'Approvals $count';
  }

  @override
  String agentsWorkersCount(int count, int max) {
    return 'Workers $count/$max';
  }

  @override
  String agentsCapabilitySkillsCount(int count) {
    return 'Skills $count';
  }

  @override
  String agentsCapabilityKnowledgeCount(int count) {
    return 'Knowledge $count';
  }

  @override
  String agentsCapabilityMemoryCount(int count) {
    return 'Memory $count';
  }

  @override
  String agentsCapabilityToolsCount(int count) {
    return 'Tools $count';
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
  String get agentsSelfLearningOn => 'Self-learning on';

  @override
  String get agentsNoCapabilityResources => 'No capability resources bound';

  @override
  String agentsDialogTitleWithName(String title, String name) {
    return '$title · $name';
  }

  @override
  String get agentsActivitiesEmptyTitle => 'No activities yet.';

  @override
  String get agentsLogsEmptyTitle => 'No Skill, Memory, MCP, or tool logs yet.';

  @override
  String get agentsApprovalsEmptyTitle => 'No approval requests.';

  @override
  String get agentsListEmptyBody =>
      'Entries appear here after the agent starts working.';

  @override
  String agentsMinWorkersCount(int count) {
    return 'Min $count';
  }

  @override
  String agentsMaxWorkersCount(int count) {
    return 'Max $count';
  }

  @override
  String get agentsNoWorkersTitle => 'No workers';

  @override
  String get agentsNoWorkersBody =>
      'Workers are prepared from the configured minimum size.';

  @override
  String agentsWorkerSubtitle(String status, int done, int priority) {
    return '$status · Done $done · Priority $priority';
  }

  @override
  String get agentsPublishTask => 'Publish task';

  @override
  String get agentsNoTasksTitle => 'No tasks';

  @override
  String get agentsNoTasksBody =>
      'Publish tasks here; workers will execute and report results.';

  @override
  String get agentsAuditRequests => 'Requests';

  @override
  String get agentsAuditCompleted => 'Completed';

  @override
  String get agentsAuditUtilization => 'Utilization';

  @override
  String get agentsRecentAuditEvents => 'Recent audit events';

  @override
  String get agentsNoAuditData => 'No audit data yet.';

  @override
  String get agentsNoKpiTitle => 'No KPI items';

  @override
  String get agentsNoKpiBody =>
      'Add KPI items in the editor so the agent can plan against them.';

  @override
  String get agentsMetricMemory => 'Memory';

  @override
  String get agentsMetricDisk => 'Disk';

  @override
  String get agentsMetricPersisted => 'Persisted';

  @override
  String get agentsMetricHandles => 'Handles';

  @override
  String get agentsPublish => 'Publish';

  @override
  String get agentsTaskTitleLabel => 'Title';

  @override
  String get agentsDescriptionLabel => 'Description';

  @override
  String get agentsContentLabel => 'Content';

  @override
  String get agentsNoteLabel => 'Note';

  @override
  String get agentsDeleteConfirmTitle => 'Delete agent';

  @override
  String agentsDeleteConfirmMessage(String name) {
    return 'Delete $name? Bound skills, knowledge, and MCP servers are kept.';
  }

  @override
  String get agentsTabProfile => 'Profile';

  @override
  String get agentsTabCapabilities => 'Capabilities';

  @override
  String get agentsTabRuntime => 'Runtime';

  @override
  String get agentsTabGovernance => 'Governance';

  @override
  String get agentsTabMetadata => 'Metadata';

  @override
  String get agentsFieldAvatar => 'Avatar';

  @override
  String get agentsFieldAvatarHint => 'Text, emoji, or image marker';

  @override
  String get agentsFieldNameRequired => 'Name *';

  @override
  String get agentsFieldPosition => 'Position';

  @override
  String get agentsFieldDepartment => 'Department';

  @override
  String get agentsFieldLevel => 'Level';

  @override
  String get agentsFieldIntroduction => 'Introduction';

  @override
  String get agentsFieldArchive => 'Archive';

  @override
  String get agentsFieldRouteFrontMatter => 'Route front matter';

  @override
  String get agentsFieldWelcomeMessage => 'Welcome message';

  @override
  String get agentsFieldPersona => 'Persona';

  @override
  String get agentsFieldResponsibilityBoundary => 'Responsibility boundary';

  @override
  String get agentsKnowledgeBase => 'Knowledge Base';

  @override
  String get agentsBuiltInTools => 'Built-in tools';

  @override
  String get agentsModelLabel => 'Model';

  @override
  String get agentsEnableAgentTitle => 'Enable agent';

  @override
  String get agentsEnableAgentBody =>
      'Enables the agent loop and agent built-in tools.';

  @override
  String get agentsSelfLearningTitle => 'Self-learning';

  @override
  String get agentsSelfLearningBody =>
      'Uses Hermes Agent to learn skills, memory, and experience.';

  @override
  String get agentsFieldWorkspacePath => 'Workspace path';

  @override
  String get agentsFieldWorkspaceScope => 'Workspace scope';

  @override
  String get agentsCrons => 'Crons';

  @override
  String get agentsClusterScaling => 'Cluster scaling';

  @override
  String get agentsMinWorkersLabel => 'Min workers';

  @override
  String get agentsMaxWorkersLabel => 'Max workers';

  @override
  String get agentsMaxRetriesLabel => 'Max retries';

  @override
  String get agentsSchedulerPolicyLabel => 'Scheduler policy';

  @override
  String get agentsTaskLabelsLabel => 'Task labels';

  @override
  String get agentsFieldName => 'Name';

  @override
  String get agentsFieldTarget => 'Target';

  @override
  String get agentsMetadataInfoTitle => 'Permission and profile metadata';

  @override
  String get agentsNoOptionsAvailable => 'No options available.';

  @override
  String get agentExecutionModeNormal => 'Default';

  @override
  String get agentExecutionModeFullAccess => 'Full access';

  @override
  String get agentLifecycleStopped => 'Stopped';

  @override
  String get agentLifecycleRunning => 'Running';

  @override
  String get agentLifecyclePaused => 'Paused';

  @override
  String get agentLifecycleDegraded => 'Degraded';

  @override
  String get agentTaskStatusBacklog => 'Backlog';

  @override
  String get agentTaskStatusReady => 'Ready';

  @override
  String get agentTaskStatusRunning => 'Running';

  @override
  String get agentTaskStatusWaitingApproval => 'Approval';

  @override
  String get agentTaskStatusPaused => 'Paused';

  @override
  String get agentTaskStatusCompleted => 'Completed';

  @override
  String get agentTaskStatusFailed => 'Failed';

  @override
  String get agentTaskStatusCanceled => 'Canceled';

  @override
  String get agentApprovalStatusPending => 'Pending';

  @override
  String get agentApprovalStatusApproved => 'Approved';

  @override
  String get agentApprovalStatusRejected => 'Rejected';

  @override
  String get agentApprovalStatusExpired => 'Expired';

  @override
  String get agentWorkerStatusIdle => 'Idle';

  @override
  String get agentWorkerStatusBusy => 'Busy';

  @override
  String get agentWorkerStatusDraining => 'Draining';

  @override
  String get agentWorkerStatusOffline => 'Offline';

  @override
  String get agentsActivityAgentStarted => 'Agent started';

  @override
  String get agentsActivityAgentStopped => 'Agent stopped';

  @override
  String get agentsActivityTaskPublished => 'Task published';

  @override
  String get agentsActivityTaskUpdated => 'Task updated';

  @override
  String get agentsActivityTaskCanceled => 'Task canceled';

  @override
  String get agentsActivityTaskPaused => 'Task paused';

  @override
  String get agentsActivityTaskTerminated => 'Task terminated';

  @override
  String get agentsActivityTaskResumed => 'Task resumed';

  @override
  String get hookEventSessionStart => 'Session Start';

  @override
  String get hookEventUserPromptSubmit => 'User Prompt Submit';

  @override
  String get hookEventPreToolUse => 'Pre-Tool Use';

  @override
  String get hookEventPostToolUse => 'Post-Tool Use';

  @override
  String get hookEventSubagentStart => 'Subagent Start';

  @override
  String get hookEventSubagentStop => 'Subagent Stop';

  @override
  String get hookEventStop => 'Stop';

  @override
  String get hookEventPreCompact => 'Pre-Compact';

  @override
  String get hookEventSessionEnd => 'Session End';

  @override
  String get hookEventErrorOccurred => 'Error Occurred';

  @override
  String get builtinToolLoadStrategyEagerShort => 'Eager';

  @override
  String get builtinToolLoadStrategyLazy => 'Lazy';

  @override
  String get builtinToolLoadStrategyDeferred => 'Deferred';

  @override
  String get builtinToolLoadStrategyEagerFull => 'Eager';

  @override
  String get builtinToolCustomBadge => 'Custom';

  @override
  String get builtinToolForceBadge => 'Force';

  @override
  String get builtinToolMoveUp => 'Move Up';

  @override
  String get builtinToolMoveDown => 'Move Down';

  @override
  String builtinToolEditorTitle(String kind) {
    return 'Edit Tool — $kind';
  }

  @override
  String get builtinToolEnableTitle => 'Enable Tool';

  @override
  String get builtinToolEnableBody =>
      'When disabled, this tool will not appear in the model\'s tool catalog.';

  @override
  String get builtinToolDisplayNameLabel => 'Display Name (optional)';

  @override
  String get builtinToolDisplayNameHelper =>
      'Overrides the default tool name. Leave blank for the built-in default.';

  @override
  String get builtinToolSummaryLabel => 'Summary (optional)';

  @override
  String get builtinToolSummaryHelper =>
      'Shown in the tool list for quick reference.';

  @override
  String get builtinToolPromptOverrideLabel => 'Prompt Override (optional)';

  @override
  String get builtinToolPromptOverrideHelper =>
      'Appended to the tool description. Use it to fine-tune how the model uses this tool.';

  @override
  String get builtinToolSchemaOverrideLabel =>
      'Schema Override (JSON, optional)';

  @override
  String get builtinToolSchemaOverrideHelper =>
      'Full JSON Schema object to override the tool\'s input parameters. Leave blank for default.';

  @override
  String get builtinToolPriorityLabel => 'Priority (0–9999)';

  @override
  String get builtinToolPriorityHelper => 'Lower = higher priority';

  @override
  String get builtinToolLoadStrategyLabel => 'Load Strategy';

  @override
  String get builtinToolForceLoadTitle => 'Force load';

  @override
  String get builtinToolForceLoadBody =>
      'When enabled, this schema is sent directly even when built-in lazy loading is Auto or On.';

  @override
  String get builtinToolMaxOutputLabel => 'Max Output (chars)';

  @override
  String get builtinToolGlobalDefaultHint => 'Global default';

  @override
  String get builtinToolTagsLabel => 'Tags (comma-separated)';

  @override
  String get builtinToolTagsHelper => 'e.g. io, file, dangerous';

  @override
  String get builtinToolRequireConfirmationTitle => 'Require Confirmation';

  @override
  String get builtinToolRequireConfirmationBody =>
      'Whether to prompt user confirmation before execution. “Default” uses the tool\'s built-in behavior.';

  @override
  String get builtinToolConfirmationDefault => 'Default';

  @override
  String get builtinToolConfirmationYes => 'Yes';

  @override
  String get builtinToolConfirmationNo => 'No';

  @override
  String get memoryTitleField => 'Title (optional)';

  @override
  String get memoryTitleHint =>
      'Summarize this memory in one sentence; leave blank to use a content preview';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonOk => 'OK';

  @override
  String get commonExport => 'Export';

  @override
  String get appUpdateDialogTitle => 'Check for Updates';

  @override
  String get appUpdateChecking => 'Checking for updates...';

  @override
  String appUpdateCurrentVersion(Object version) {
    return 'Current: $version';
  }

  @override
  String appUpdateNewVersion(Object version) {
    return 'New version: v$version';
  }

  @override
  String appUpdatePublished(Object date) {
    return 'Published: $date';
  }

  @override
  String appUpdateFileSize(Object size) {
    return 'Size: $size';
  }

  @override
  String get appUpdateAlreadyLatestTitle => 'You\'re up to date';

  @override
  String appUpdateAlreadyLatestBody(Object version) {
    return 'OpenHand $version is the latest version.';
  }

  @override
  String get appUpdateDownloadComplete => 'Download Complete';

  @override
  String get appUpdateDownloading => 'Downloading...';

  @override
  String get appUpdateCheckFailed => 'Update Check Failed';

  @override
  String get appUpdateLater => 'Later';

  @override
  String get appUpdateDownload => 'Download';

  @override
  String get exportRangeInvalid => 'Enter a valid range (1 ≤ start ≤ end)';

  @override
  String get exportRangeStart => 'Start';

  @override
  String get exportRangeEnd => 'End';

  @override
  String get exportSessionSettingsTitle => 'Export Session Settings';

  @override
  String exportTotalMessages(Object count) {
    return 'Total messages available: $count';
  }

  @override
  String get exportRolesSection => 'Roles';

  @override
  String get exportAllRoles => 'All roles';

  @override
  String get exportMessageKindsSection => 'Message Kinds';

  @override
  String get exportAllKinds => 'All kinds';

  @override
  String get exportMessageRangeSection => 'Message Range';

  @override
  String get exportOnlyRange => 'Export only a range (1-based, inclusive)';

  @override
  String get exportOtherOptions => 'Other Options';

  @override
  String get exportIncludeDeleted => 'Include deleted messages';

  @override
  String get exportPickOneRole => 'Pick at least one role.';

  @override
  String get exportPickOneMessageKind => 'Pick at least one message kind.';

  @override
  String get exportRoleSystem => 'System';

  @override
  String get exportRoleUser => 'User';

  @override
  String get exportRoleAssistant => 'Assistant';

  @override
  String get exportRoleTool => 'Tool';

  @override
  String get exportKindUser => 'User message';

  @override
  String get exportKindAssistant => 'Assistant reply';

  @override
  String get exportKindReasoning => 'Reasoning';

  @override
  String get exportKindToolCall => 'Tool call';

  @override
  String get exportKindTool => 'Tool result';

  @override
  String get exportKindCompressionPoint => 'Compression point';

  @override
  String get exportKindMcp => 'MCP event';

  @override
  String get exportKindSkill => 'Skill event';

  @override
  String get exportKindHook => 'Hook event';

  @override
  String get exportKindSelfLearning => 'Self-learning';

  @override
  String get exportKindFileMutationSummary => 'File change summary';

  @override
  String get exportKindStatus => 'Status message';

  @override
  String get exportPhaseLogRangeSection => 'Phase Log Range';

  @override
  String exportTotalPhaseLogs(Object count) {
    return 'Total phase logs available: $count';
  }

  @override
  String get modelSearchHint => 'Search models…';

  @override
  String modelSearchResultCount(Object filtered, Object total) {
    return '$filtered / $total models';
  }

  @override
  String get modelSearchNoAvailableModels => 'No available models';

  @override
  String get modelSearchNoMatchingModels => 'No matching models';

  @override
  String get modelSearchRecent => 'Recent';

  @override
  String get nativeAudioLoadFailed =>
      'Unable to load audio. Open with the system player instead.';

  @override
  String get nativeAudioPlaybackFailed =>
      'Playback failed. Try again or open with the system player.';

  @override
  String get nativeAudioBack15Seconds => 'Back 15 s';

  @override
  String get nativeAudioPause => 'Pause';

  @override
  String get nativeAudioPlay => 'Play';

  @override
  String get nativeAudioForward15Seconds => 'Forward 15 s';

  @override
  String get nativeAudioMute => 'Mute';

  @override
  String get nativeAudioUnmute => 'Unmute';

  @override
  String get nativeAudioSystemPlayer => 'System Player';

  @override
  String get nativeAudioSequencePlayback => 'Sequence playback';

  @override
  String get nativeAudioRepeatOne => 'Repeat one';

  @override
  String get nativeAudioShufflePlayback => 'Shuffle playback';

  @override
  String nativeAudioEffectTooltip(Object effect) {
    return 'Effect: $effect';
  }

  @override
  String get nativeAudioEffectStandard => 'Standard';

  @override
  String get nativeAudioEffectSpatial => '3D';

  @override
  String get nativeAudioEffectVocal => 'Vocal';

  @override
  String get nativeAudioEffectWarm => 'Warm';

  @override
  String get hooksTitle => 'Hooks';

  @override
  String get hooksSubtitle =>
      'Configure scripts to run at each AI agent lifecycle stage. Hooks execute sequentially when the corresponding event fires.';

  @override
  String get hooksNew => 'New Hook';

  @override
  String get hooksDeleteTitle => 'Delete Hook';

  @override
  String hooksDeleteMessage(Object label) {
    return 'Delete \"$label\"? This action cannot be undone.';
  }

  @override
  String get hooksEmptyTitle => 'No hooks configured yet';

  @override
  String get hooksEmptyBody => 'Click \"New Hook\" above to get started.';

  @override
  String get hooksTimeoutTooltip => 'Timeout';

  @override
  String hooksInlineScriptDescription(Object firstLine) {
    return 'Inline: $firstLine';
  }

  @override
  String get hooksNoScriptConfigured => 'No script configured';

  @override
  String get hooksEditTitle => 'Edit Hook';

  @override
  String get hooksLabelField => 'Label';

  @override
  String get hooksLabelHint => 'e.g. Logging';

  @override
  String get hooksTriggerEvent => 'Trigger Event';

  @override
  String get hooksScriptSource => 'Script Source';

  @override
  String get hooksScriptSourceFile => 'File';

  @override
  String get hooksScriptSourceInline => 'Inline';

  @override
  String get hooksScriptFilePath => 'Script File Path';

  @override
  String get hooksScriptFileHint => 'Select a .sh / .ps1 / .bat file';

  @override
  String get hooksBrowse => 'Browse';

  @override
  String get hooksScriptContextFileHelp =>
      'Context JSON is passed in two safe ways (both work with jq):\n① Temp file: jq -r .session_id \"\$OPENHAND_HOOK_CONTEXT_FILE\"\n② Raw stdin: jq -r .session_id\nFields: session_id, session_file_path, environment, etc.';

  @override
  String get hooksInlineWindowsHint => 'Enter PowerShell / BAT script';

  @override
  String get hooksInlineShellHint =>
      'Enter shell script (#!/bin/bash not required)';

  @override
  String get hooksScriptContextInlineHelp =>
      'Context JSON is passed in two safe ways (both work with jq):\n① Temp file: SID=\$(jq -r .session_id \"\$OPENHAND_HOOK_CONTEXT_FILE\")\n② Raw stdin: SID=\$(jq -r .session_id)\nFields: session_id, session_file_path, environment, statistics, etc.';

  @override
  String get hooksTimeoutSeconds => 'Timeout (seconds)';

  @override
  String get hooksEnabled => 'Enabled';

  @override
  String get hooksValidationLabelRequired => 'Enter a hook label.';

  @override
  String get hooksValidationScriptFileRequired => 'Select a script file.';

  @override
  String get hooksValidationInlineScriptRequired =>
      'Enter inline script content.';

  @override
  String get hooksFileTypeScripts => 'Scripts';

  @override
  String get hooksFileTypeShellScripts => 'Shell Scripts';

  @override
  String get hooksFileTypeAllFiles => 'All Files';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get choiceInputCustomOptionLabel => 'Custom input';

  @override
  String get choiceInputCustomInputHint => 'Type your answer here…';

  @override
  String get choiceInputCustomOptionDescription =>
      'Pick this to type your own answer';

  @override
  String get mediaPreviewImageCopied => 'Copied image to clipboard.';

  @override
  String get mediaPreviewImageFileOrPathCopied =>
      'Copied image file or path to clipboard.';

  @override
  String get mediaPreviewMediaFileCopied => 'Copied media file to clipboard.';

  @override
  String get mediaPreviewDirectCopyUnavailablePathCopied =>
      'Direct media file copy is unavailable on this platform. Copied the file path.';

  @override
  String get mediaPreviewMediaUrlCopied => 'Copied media URL.';

  @override
  String get mediaPreviewDirectCopyUnavailableTempPathCopied =>
      'Direct media file copy is unavailable on this platform. Copied the temporary file path.';

  @override
  String get mediaPreviewDataCopyFailedUrlCopied =>
      'Unable to copy media data. Copied the source URL.';

  @override
  String mediaPreviewCopyFailed(Object error) {
    return 'Copy failed: $error';
  }

  @override
  String get mediaPreviewNoSource => 'Media source is unavailable.';

  @override
  String get knowledgeVectorDistributionTitle => 'Vector Distribution';

  @override
  String get knowledgeVectorDistributionLoading =>
      'Sampling and projecting vectors.';

  @override
  String get knowledgeVectorDistributionEmpty =>
      'The current collection has no vectors to display.';

  @override
  String get knowledgeVectorProjectionSection => 'Projection';

  @override
  String get knowledgeVectorAlgorithm => 'Algorithm';

  @override
  String get knowledgeVectorOriginalDimensions => 'Original dimensions';

  @override
  String get knowledgeVectorVisiblePoints => 'Visible points';

  @override
  String get knowledgeVectorSampled => 'Sampled';

  @override
  String get knowledgeVectorDurationMs => 'Duration ms';

  @override
  String get knowledgeVectorResample => 'Resample';

  @override
  String get qdrantStatusRefreshIncomplete =>
      'Qdrant status refresh returned incomplete data.';

  @override
  String get qdrantStatusRawVectorEmpty => 'Enter a raw vector first.';

  @override
  String qdrantStatusRawVectorInvalid(Object value) {
    return 'Invalid vector number: $value';
  }

  @override
  String qdrantStatusRawVectorDimensionMismatch(int actual, int expected) {
    return 'Raw vector has $actual dimensions; current settings require $expected.';
  }

  @override
  String get qdrantStatusPointIdsEmpty => 'Enter point/chunk IDs first.';

  @override
  String get qdrantStatusPayloadIndexesSubmitted =>
      'Default payload index creation submitted.';

  @override
  String get qdrantStatusDangerousOpsDisabled =>
      'Enable dangerous admin operations in Knowledge Base settings first.';

  @override
  String get qdrantStatusDeletePointIdsEmpty =>
      'Enter point IDs to delete first.';

  @override
  String get qdrantStatusDeletePointsTitle => 'Delete Qdrant points?';

  @override
  String qdrantStatusDeletePointsMessage(int count) {
    return 'This deletes $count points from the current collection. This cannot be undone.';
  }

  @override
  String get qdrantStatusDeletePointsConfirm => 'Delete points';

  @override
  String get qdrantStatusPointsDeleted => 'Points deleted.';

  @override
  String get qdrantStatusDeleteCollectionTitle => 'Delete Qdrant collection?';

  @override
  String qdrantStatusDeleteCollectionMessage(Object collection) {
    return 'This deletes collection \"$collection\" and all points in it. This cannot be undone.';
  }

  @override
  String get qdrantStatusDeleteCollectionConfirm => 'Delete collection';

  @override
  String get qdrantStatusCollectionDeleted => 'Collection deleted.';

  @override
  String get qdrantStatusDiagnosticsCopied => 'Diagnostics copied.';

  @override
  String get qdrantStatusTitle => 'Qdrant Operations';

  @override
  String get qdrantStatusTabOverview => 'Overview';

  @override
  String get qdrantStatusTabCollections => 'Collections';

  @override
  String get qdrantStatusTabPoints => 'Points';

  @override
  String get qdrantStatusTabDiagnostics => 'Diagnostics';

  @override
  String get qdrantStatusRefresh => 'Refresh';

  @override
  String get qdrantStatusCopyDiagnostics => 'Copy diagnostics';

  @override
  String get qdrantStatusHeaderTitle => 'Local vector database status';

  @override
  String get qdrantStatusMetricCollections => 'Collections';

  @override
  String get qdrantStatusMetricPoints => 'Points';

  @override
  String get qdrantStatusMetricIndexedVectors => 'Indexed vectors';

  @override
  String get qdrantStatusMetricChunks => 'Chunks';

  @override
  String get qdrantStatusMetricPendingJobs => 'Pending jobs';

  @override
  String get qdrantStatusMetricWalCapacity => 'WAL capacity';

  @override
  String get qdrantStatusSmoothTrend => 'Smooth Trend';

  @override
  String get qdrantStatusNoCollections =>
      'No collection found, or Qdrant is unavailable.';

  @override
  String get qdrantStatusPointsSectionTitle => 'Points / Search / Scroll';

  @override
  String get qdrantStatusPointIdsLabel => 'Point / chunk IDs';

  @override
  String get qdrantStatusSourceFilterLabel => 'Source ID filter';

  @override
  String get qdrantStatusTagFilterLabel => 'Tag filter';

  @override
  String get qdrantStatusLimitLabel => 'Limit';

  @override
  String get qdrantStatusRawVectorLabel =>
      'Raw vector (comma or space separated, must match dimensions)';

  @override
  String get qdrantStatusQueryIds => 'Query IDs';

  @override
  String get qdrantStatusScrollFilter => 'Scroll / Filter';

  @override
  String get qdrantStatusRawVectorSearch => 'Raw Vector Search';

  @override
  String get qdrantStatusRebuildPayloadIndexes => 'Rebuild payload indexes';

  @override
  String get qdrantStatusDeletePoints => 'Delete Points';

  @override
  String get qdrantStatusOperationResult => 'Operation Result';

  @override
  String get qdrantStatusRawDiagnosticsJson => 'Raw Diagnostics JSON';

  @override
  String get qdrantStatusNoDiagnostics => 'No diagnostics yet.';

  @override
  String get qdrantStatusLatestOperationResult => 'Latest Operation Result';

  @override
  String get qdrantStatusOperationLog => 'Operation Log';

  @override
  String get qdrantStatusNoOperations => 'No operations yet.';

  @override
  String get qdrantStatusCollectingSamples =>
      'Collecting samples for trend view.';

  @override
  String get qdrantStatusTrendPoints => 'points';

  @override
  String get qdrantStatusTrendChunks => 'chunks';

  @override
  String get qdrantStatusTrendPendingFailed => 'pending/failed';

  @override
  String qdrantStatusTrendSampleCount(int count) {
    return '$count pts';
  }

  @override
  String get qdrantSectionOverview => 'Overview';

  @override
  String get qdrantSectionDockerContainer => 'Docker / Container';

  @override
  String get qdrantSectionApiMetrics => 'Qdrant API Metrics';

  @override
  String get qdrantSectionCollectionConfig => 'Collection Config';

  @override
  String get qdrantSectionStorageOptimizer => 'Storage / Optimizer';

  @override
  String get qdrantSectionTelemetry => 'Telemetry';

  @override
  String get qdrantSectionOpenHandKnowledge => 'OpenHand Knowledge';

  @override
  String get qdrantMetricServiceStatus => 'Service status';

  @override
  String get qdrantMetricRestEndpoint => 'REST endpoint';

  @override
  String get qdrantMetricGrpcEndpoint => 'gRPC endpoint';

  @override
  String get qdrantMetricQdrantVersion => 'Qdrant version';

  @override
  String get qdrantMetricCurrentCollection => 'Current collection';

  @override
  String get qdrantMetricCollectionStatus => 'Collection status';

  @override
  String get qdrantMetricOptimizerStatus => 'Optimizer status';

  @override
  String get qdrantMetricLastHealthCheck => 'Last health check';

  @override
  String get qdrantMetricDockerDaemon => 'Docker daemon';

  @override
  String get qdrantMetricContainerCpu => 'Container CPU';

  @override
  String get qdrantMetricContainerMemory => 'Container memory';

  @override
  String get qdrantMetricNetworkIo => 'Network I/O';

  @override
  String get qdrantMetricBlockIo => 'Block I/O';

  @override
  String get qdrantMetricRestartCount => 'Restart count';

  @override
  String get qdrantMetricLatestLogSummary => 'Latest log summary';

  @override
  String get qdrantMetricCollectionsTotal => 'Collections total';

  @override
  String get qdrantMetricPointsTotal => 'Points total';

  @override
  String get qdrantMetricVectorsTotal => 'Vectors total';

  @override
  String get qdrantMetricIndexedVectorsTotal => 'Indexed vectors total';

  @override
  String get qdrantMetricSegmentsTotal => 'Segments';

  @override
  String get qdrantMetricPayloadSchemaFields => 'Payload schema fields';

  @override
  String get qdrantMetricPayloadSchemaNames => 'Payload schema names';

  @override
  String get qdrantMetricVectorSize => 'Vector size';

  @override
  String get qdrantMetricDistance => 'Distance';

  @override
  String get qdrantMetricSingleNodeMode => 'Single-node mode';

  @override
  String get qdrantMetricPayloadIndexStatus => 'Payload index status';

  @override
  String get qdrantMetricClusterStatus => 'Cluster status';

  @override
  String get qdrantMetricHnswM => 'HNSW M';

  @override
  String get qdrantMetricHnswEfConstruct => 'HNSW ef_construct';

  @override
  String get qdrantMetricHnswFullScanThreshold => 'HNSW full scan threshold';

  @override
  String get qdrantMetricHnswMaxIndexingThreads => 'HNSW max indexing threads';

  @override
  String get qdrantMetricOnDiskPayload => 'On-disk payload';

  @override
  String get qdrantMetricShardNumber => 'Shard number';

  @override
  String get qdrantMetricReplicationFactor => 'Replication factor';

  @override
  String get qdrantMetricWriteConsistencyFactor => 'Write consistency factor';

  @override
  String get qdrantMetricReadFanOutFactor => 'Read fan-out factor';

  @override
  String get qdrantMetricOptimizerDeletedThreshold =>
      'Optimizer deleted threshold';

  @override
  String get qdrantMetricOptimizerVacuumMinVectorNumber =>
      'Vacuum min vector number';

  @override
  String get qdrantMetricOptimizerDefaultSegmentNumber =>
      'Default segment number';

  @override
  String get qdrantMetricOptimizerMaxSegmentSize => 'Max segment size';

  @override
  String get qdrantMetricOptimizerIndexingThreshold => 'Indexing threshold';

  @override
  String get qdrantMetricOptimizerFlushIntervalSeconds =>
      'Flush interval seconds';

  @override
  String get qdrantMetricWalCapacityMb => 'WAL capacity MB';

  @override
  String get qdrantMetricWalSegmentsAhead => 'WAL segments ahead';

  @override
  String get qdrantMetricQuantization => 'Quantization';

  @override
  String get qdrantMetricStrictMode => 'Strict mode';

  @override
  String get qdrantMetricTelemetryStatus => 'Telemetry status';

  @override
  String get qdrantMetricAppVersion => 'App version';

  @override
  String get qdrantMetricAppName => 'App name';

  @override
  String get qdrantMetricTelemetryCollections => 'Collections telemetry';

  @override
  String get qdrantMetricTelemetryRequests => 'Requests telemetry';

  @override
  String get qdrantMetricSourceCount => 'Sources';

  @override
  String get qdrantMetricChunkCount => 'Chunks';

  @override
  String get qdrantMetricPendingEmbeddingJobs => 'Pending embedding jobs';

  @override
  String get qdrantMetricFailedEmbeddingJobs => 'Failed embedding jobs';

  @override
  String get qdrantMetricEmbeddingModel => 'Current embedding model';

  @override
  String get qdrantMetricEmbeddingDimensions => 'Current dimensions';

  @override
  String get qdrantMetricRetrievalTopN => 'Retrieval topN';

  @override
  String get qdrantMetricRetrievalTopK => 'Final topK';

  @override
  String get qdrantMetricMinSimilarity => 'Minimum similarity';

  @override
  String get qdrantMetricPromptChunkBudget => 'Prompt chunk budget';

  @override
  String get qdrantMetricPromptTokenBudget => 'Prompt token budget';

  @override
  String get qdrantValueYes => 'Yes';

  @override
  String get qdrantValueNo => 'No';

  @override
  String get qdrantValueHealthy => 'Healthy';

  @override
  String get qdrantValueUnknown => 'Unknown';

  @override
  String get qdrantValueLoading => 'Loading';

  @override
  String get qdrantValueAvailable => 'Available';

  @override
  String get qdrantValueUnavailable => 'Unavailable';

  @override
  String get qdrantValuePluginServiceScan => 'Scanned by plugin service';

  @override
  String get qdrantValuePluginRuntimeMetric => 'Provided by plugin runtime';

  @override
  String get qdrantValuePluginDetailsLogs => 'Available in plugin details';

  @override
  String get qdrantValueLocalSingleNodeOrUnavailable =>
      'Local single-node / unavailable';

  @override
  String get qdrantValueClusterInfoAvailable => 'Cluster info returned';

  @override
  String get qdrantValuePayloadSchemaConfigured => 'Payload schema configured';

  @override
  String get qdrantValuePayloadSchemaMissing => 'No payload schema found';
}
