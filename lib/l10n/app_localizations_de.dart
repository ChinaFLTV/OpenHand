// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'OpenHand';

  @override
  String get appTagline =>
      'Eine offene, stabile und erweiterbare Desktop-Arbeitsfläche';

  @override
  String get newThread => 'Neuer Thread';

  @override
  String get skills => 'Fähigkeiten';

  @override
  String get memory => 'Speicher';

  @override
  String get mcp => 'MCP';

  @override
  String get settings => 'Einstellungen';

  @override
  String get threads => 'Konversationen';

  @override
  String get threadsLoadMore => 'Weitere Konversationen laden';

  @override
  String get composerHint =>
      'Frage OpenHand alles, nutze / für Aktionen und @ für Kontext';

  @override
  String get composerSend => 'Senden';

  @override
  String get chatSending => 'Senden';

  @override
  String get chatRequestFailed =>
      'Modellanfrage fehlgeschlagen. Modellkonfiguration, Netzwerkverbindung oder Protokolltyp prüfen.';

  @override
  String get placeholderComingSoon =>
      'Weitere Module werden hier schrittweise ergänzt.';

  @override
  String get settingsTitle => 'Einstellungszentrum';

  @override
  String get settingsSubtitle =>
      'Hier verwaltest du Thema, Sprache und App-Informationen.';

  @override
  String get settingsFilePathLabel => 'Einstellungsdatei';

  @override
  String get themeSectionTitle => 'App-Thema';

  @override
  String get themeSectionBody =>
      'Wähle den Helligkeitsstil, der zu deiner aktuellen Arbeitsumgebung passt.';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get themePaletteSectionTitle => 'Themen-Palette';

  @override
  String get themePaletteSectionBody =>
      'Wählen Sie eine globale Farbvoreinstellung. OpenHand leitet daraus die Material 3 Expressive-Flächen und -Akzente ab.';

  @override
  String get themePresetDarkNightPurple => 'Dunkelnacht-Lila';

  @override
  String get themePresetDeepSeaBlue => 'Tiefseeblau';

  @override
  String get themePresetMistGray => 'Nebelgrau';

  @override
  String get themePresetObsidianBlack => 'Obsidian-Schwarz';

  @override
  String get themePresetPolarWhite => 'Polarweiß';

  @override
  String get themePresetFrostMorningBlue => 'Frostmorgenblau';

  @override
  String get themePresetDuskMountainGreen => 'Dämmerungsbergrün';

  @override
  String get themePresetNebulaPurple => 'Nebel-Lila';

  @override
  String get themePresetEmberOrange => 'Glut-Orange';

  @override
  String get themePresetTundraGreen => 'Tundra-Grün';

  @override
  String get themePresetMoonShadowSilver => 'Mondschattensilber';

  @override
  String get themePresetAmberGold => 'Bernsteingold';

  @override
  String get themePresetRainyCyan => 'Regen-Cyan';

  @override
  String get themePresetGraphiteGray => 'Graphitgrau';

  @override
  String get themePresetGlacierBlue => 'Gletscherblau';

  @override
  String get themePresetBlazeRed => 'Flammenrot';

  @override
  String get themePresetNightfallBlue => 'Abenddämmerungsblau';

  @override
  String get themePresetColdMoonWhite => 'Kaltmondweiß';

  @override
  String get themePresetPineInk => 'Kiefernschwarz';

  @override
  String get themePresetSkyCyan => 'Himmel-Cyan';

  @override
  String get languageSectionTitle => 'App-Sprache';

  @override
  String get languageSectionBody =>
      'Wechsle die Sprache der Oberfläche und wende sie sofort an.';

  @override
  String get languageSimplifiedChinese => 'Vereinfachtes Chinesisch';

  @override
  String get languageTraditionalChinese => 'Traditionelles Chinesisch';

  @override
  String get languageEnglish => 'Englisch';

  @override
  String get languageFrench => 'Französisch';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get languageJapanese => 'Japanisch';

  @override
  String get aboutSectionTitle => 'Über die App';

  @override
  String get aboutSectionBody =>
      'OpenHand befindet sich aktuell in der Grundaufbauphase und konzentriert sich auf eine stabile Desktop-Struktur, eine visuelle Basis und eine erweiterbare Architektur.';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutPackage => 'Paket';

  @override
  String get aboutPlatforms => 'Plattformen';

  @override
  String get aboutPlatformsValue => 'macOS 15+ / Windows 10+';

  @override
  String get aboutBuild => 'Build-Nummer';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonSave => 'Speichern';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonEdit => 'Bearbeiten';

  @override
  String get exportProgressCancelling => 'Wird abgebrochen…';

  @override
  String get readerFileTypeText => 'Nur Text';

  @override
  String get readerFileTypeCode => 'Code';

  @override
  String knowledgeReaderNoModelForType(Object type) {
    return 'Kein Reader-Modell kann $type lesen.';
  }

  @override
  String get permissionLabel => 'Voller Zugriff';

  @override
  String get settingsCategoryGeneral => 'Allgemein';

  @override
  String get settingsCategoryAi => 'KI';

  @override
  String get settingsCategorySkills => 'Fähigkeiten';

  @override
  String get settingsCategoryMemory => 'Speicher';

  @override
  String get mcpSectionTitle => 'MCP-Dienste';

  @override
  String get mcpSectionBody =>
      'Globalen MCP-Schalter und Konfigurationsdateipfad der Dienste verwalten. Erstellen, Aktualisieren, Löschen und Aktivieren von Diensten werden mit der MCP-JSON-Datei synchronisiert.';

  @override
  String get mcpEnabledLabel => 'MCP-Dienste aktivieren';

  @override
  String get mcpEnabledBody =>
      'Wenn deaktiviert, bleiben gespeicherte Serverkonfigurationen erhalten, MCP-Funktionen sind zur Laufzeit jedoch ausgeschaltet.';

  @override
  String get mcpFilePathLabel => 'MCP-Konfigurationsdatei';

  @override
  String get mcpOpenDirectory => 'Verzeichnis öffnen';

  @override
  String get mcpStdioCacheResetAction => 'stdio-Paketcache zurücksetzen';

  @override
  String get mcpStdioCacheResetConfirmTitle =>
      'Isolierten stdio-Paketcache zurücksetzen?';

  @override
  String get mcpStdioCacheResetConfirmBody =>
      'Dies löscht die npm-/uv-/pip-Caches unter ~/.openhand/mcp/package-cache. Beim nächsten Start eines stdio-MCP-Servers werden Abhängigkeiten erneut geladen. Das globale ~/.npm bleibt unberührt.';

  @override
  String get mcpStdioCacheResetConfirm => 'Zurücksetzen';

  @override
  String get mcpStdioCacheResetCancel => 'Abbrechen';

  @override
  String get mcpStdioCacheResetDone => 'Isolierter Cache wurde geleert.';

  @override
  String get mcpStdioCacheResetFailed =>
      'Zurücksetzen fehlgeschlagen. Bitte ~/.openhand/mcp/package-cache manuell löschen.';

  @override
  String get pluginServiceTitle => 'Plugins';

  @override
  String get pluginServiceSubtitle =>
      'Optionale Plugins installieren, aktualisieren und entfernen. Plugins erweitern OpenHand um zusätzliche Laufzeitfunktionen.';

  @override
  String get pluginServiceRescan => 'Erneut scannen';

  @override
  String get pluginServiceScanning => 'Lokale Plugin-Umgebung wird gescannt…';

  @override
  String get pluginServiceScanFailed => 'Plugin-Scan fehlgeschlagen';

  @override
  String get pluginServiceActionInstall => 'Installieren';

  @override
  String get pluginServiceActionUpdate => 'Aktualisieren';

  @override
  String get pluginServiceActionUninstall => 'Deinstallieren';

  @override
  String get pluginServiceActionEnable => 'Aktivieren';

  @override
  String get pluginServiceActionDisable => 'Deaktivieren';

  @override
  String get pluginServiceStatusInstalled => 'Installiert';

  @override
  String get pluginServiceStatusNotInstalled => 'Nicht installiert';

  @override
  String get pluginServiceStatusInstalling => 'Wird installiert…';

  @override
  String get pluginServiceStatusUpdating => 'Wird aktualisiert…';

  @override
  String get pluginServiceStatusUninstalling => 'Wird deinstalliert…';

  @override
  String get pluginServiceStatusError => 'Fehler';

  @override
  String get pluginServiceCheckUpdates => 'Updates prüfen';

  @override
  String get pluginServiceMcpService => 'MCP-Dienst';

  @override
  String pluginServiceInstallDependencyRequired(Object dependency) {
    return '$dependency muss zuerst installiert werden';
  }

  @override
  String pluginServiceInstallConfirmTitle(Object plugin) {
    return '$plugin installieren?';
  }

  @override
  String pluginServiceInstallConfirmMessage(Object plugin) {
    return '$plugin wird installiert. Abhängigkeiten können heruntergeladen werden.';
  }

  @override
  String pluginServiceInstallSuccess(Object plugin) {
    return '$plugin installiert';
  }

  @override
  String pluginServiceInstallFailure(Object plugin) {
    return 'Installation von $plugin fehlgeschlagen';
  }

  @override
  String pluginServiceUpdateConfirmTitle(Object plugin) {
    return '$plugin aktualisieren?';
  }

  @override
  String pluginServiceUpdateConfirmMessage(
    Object plugin,
    Object currentVersion,
    Object latestVersion,
  ) {
    return '$plugin von $currentVersion auf $latestVersion aktualisieren.';
  }

  @override
  String pluginServiceUpdateSuccess(Object plugin) {
    return '$plugin aktualisiert';
  }

  @override
  String pluginServiceUpdateFailure(Object plugin) {
    return 'Aktualisierung von $plugin fehlgeschlagen';
  }

  @override
  String get pluginServiceCheckUpdateFailed => 'Update-Prüfung fehlgeschlagen';

  @override
  String pluginServiceNewVersionAvailable(Object version) {
    return 'Neue Version verfügbar: $version';
  }

  @override
  String get pluginServiceNoUpdatesAvailable => 'Keine Updates verfügbar';

  @override
  String pluginServiceUninstallBlocked(Object dependent, Object plugin) {
    return '$dependent hängt von $plugin ab. Bitte zuerst deinstallieren.';
  }

  @override
  String pluginServiceUninstallConfirmTitle(Object plugin) {
    return '$plugin deinstallieren?';
  }

  @override
  String pluginServiceUninstallConfirmMessage(Object plugin) {
    return '$plugin wird entfernt. Diese Aktion kann nicht rückgängig gemacht werden.';
  }

  @override
  String pluginServiceUninstallSuccess(Object plugin) {
    return '$plugin deinstalliert';
  }

  @override
  String pluginServiceUninstallFailure(Object plugin) {
    return 'Deinstallation von $plugin fehlgeschlagen';
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
  String get pluginServiceRuntimeArch => 'Arch.';

  @override
  String pluginServiceLogLineCount(Object count) {
    return 'Logs: $count Zeilen';
  }

  @override
  String get pluginServiceWaitingForOutput => 'Warte auf Ausgabe…';

  @override
  String get pluginServiceExecuting => 'Wird ausgeführt…';

  @override
  String get pluginServiceCompleted => 'Abgeschlossen';

  @override
  String get pluginServiceVersion => 'Version';

  @override
  String get pluginServiceUpdateAvailable => 'Update verfügbar';

  @override
  String get pluginServiceDependsOn => 'Hängt ab von';

  @override
  String get pluginServiceRequiredBy => 'Benötigt von';

  @override
  String get pluginServiceNone => 'Keine';

  @override
  String pluginServiceDetailTitle(Object plugin) {
    return '$plugin Details';
  }

  @override
  String get pluginServiceDetailBasicInfo => 'Basisinfo';

  @override
  String get pluginServiceDetailName => 'Name';

  @override
  String get pluginServiceDetailDescription => 'Beschreibung';

  @override
  String get pluginServiceDetailStatus => 'Status';

  @override
  String get pluginServiceDetailEnvironment => 'Umgebung';

  @override
  String get pluginServiceDetailFileSystem => 'Dateisystem';

  @override
  String get pluginServiceDetailDependencies => 'Abhängigkeiten';

  @override
  String get pluginServiceThreadTemplates => 'Thread-Vorlagen';

  @override
  String get pluginServiceTemplates => 'Vorlagen';

  @override
  String get pluginServiceMcpPackage => 'MCP-Paket';

  @override
  String get pluginServiceMcpBrowserDescription =>
      'MCP-Server für Browser-Automatisierung';

  @override
  String get pluginServiceDetailProcessors => 'Prozessoren';

  @override
  String get pluginServiceDetailInstallPath => 'Installationspfad';

  @override
  String get pluginServiceDetailInstallationTarget => 'Installationsziel';

  @override
  String get pluginServiceDetailInstallMethod => 'Installationsmethode';

  @override
  String get pluginServiceDetailTargetOs => 'Zielbetriebssystem';

  @override
  String get pluginServiceDetailSupportedPlatforms =>
      'Unterstützte Plattformen';

  @override
  String get pluginServiceDetailPackageName => 'Paketname';

  @override
  String get pluginServiceDetailBinaryName => 'Befehlsname';

  @override
  String get pluginServiceDetailRepository => 'Repository';

  @override
  String get pluginServiceDetailDocumentation => 'Offizielle Dokumentation';

  @override
  String get pluginServiceDetailInstallCommand => 'Installationsbefehl';

  @override
  String get pluginServiceDetailUpgradeCommand => 'Upgrade-Befehl';

  @override
  String get pluginServiceDetailUninstallCommand => 'Deinstallationsbefehl';

  @override
  String get pluginServiceDetailExecutablePath => 'Ausführbarer Einstieg';

  @override
  String get pluginServiceDetailCacheDirectory => 'Cache-Verzeichnis';

  @override
  String get pluginServiceDetailNpmGlobalRoot => 'Globales npm-Verzeichnis';

  @override
  String get pluginServiceDetailCurrentVersion => 'Version';

  @override
  String get pluginServiceDetailLatestVersion => 'Neueste';

  @override
  String get pluginServiceDetailBoundPython => 'Gebundenes Python';

  @override
  String get pluginServiceDetailDesktopAppDetected => 'Desktop-App erkannt';

  @override
  String get pluginServiceDetailDaemonRunning => 'Daemon läuft';

  @override
  String get pluginServiceDetailCliAvailable => 'CLI verfügbar';

  @override
  String get pluginServiceDetailDockerContext => 'Docker-Kontext';

  @override
  String get pluginServiceDetailServerVersion => 'Serverversion';

  @override
  String get pluginServiceDetailDockerOs => 'Docker-OS';

  @override
  String get pluginServiceDetailDockerRootDir => 'Docker-Root-Verzeichnis';

  @override
  String get pluginServiceDetailDaemonName => 'Daemon-Name';

  @override
  String get pluginServiceDetailOsType => 'OS-Typ';

  @override
  String get pluginServiceDetailArchitecture => 'Architektur';

  @override
  String get pluginServiceDetailComposeVersion => 'Compose-Version';

  @override
  String get pluginServiceDetailDockerDaemonRunning => 'Docker-Daemon läuft';

  @override
  String get pluginServiceDetailOpenHandManaged => 'Von OpenHand verwaltet';

  @override
  String get pluginServiceDetailContainerId => 'Container-ID';

  @override
  String get pluginServiceDetailContainerName => 'Containername';

  @override
  String get pluginServiceDetailContainerStatus => 'Containerstatus';

  @override
  String get pluginServiceDetailRunning => 'Läuft';

  @override
  String get pluginServiceDetailStartedAt => 'Gestartet um';

  @override
  String get pluginServiceDetailFinishedAt => 'Beendet um';

  @override
  String get pluginServiceDetailRestartCount => 'Neustarts';

  @override
  String get pluginServiceDetailExitCode => 'Exit-Code';

  @override
  String get pluginServiceDetailImage => 'Image';

  @override
  String get pluginServiceDetailImageId => 'Image-ID';

  @override
  String get pluginServiceDetailPorts => 'Ports';

  @override
  String get pluginServiceDetailRestartPolicy => 'Neustartregel';

  @override
  String get pluginServiceDetailRestEndpoint => 'REST-Endpunkt';

  @override
  String get pluginServiceDetailGrpcEndpoint => 'gRPC-Endpunkt';

  @override
  String get pluginServiceDetailDataDirectory => 'Datenverzeichnis';

  @override
  String get pluginServiceDetailHealthResponse => 'Health-Antwort';

  @override
  String get pluginServiceDetailHealthTitle => 'Health-Titel';

  @override
  String get pluginServiceDetailCollectionCount => 'Collection-Anzahl';

  @override
  String get pluginServiceDetailRuntimeCapabilities => 'Laufzeitfunktionen';

  @override
  String get pluginServiceDetailApplicationPath => 'Anwendungspfad';

  @override
  String get pluginServiceDetailReleaseChannel => 'Veröffentlichungskanal';

  @override
  String get pluginServiceDetailVersionSource => 'Versionsquelle';

  @override
  String get pluginServiceDetailVersionApi => 'Versions-API';

  @override
  String get pluginServiceDetailBrowserKind => 'Browsertyp';

  @override
  String get pluginServiceDetailCdpTransport => 'CDP-Transport';

  @override
  String get pluginServiceDetailCdpEndpoint => 'CDP-Endpunkt';

  @override
  String get pluginServiceDetailProfileStrategy => 'Profilstrategie';

  @override
  String get pluginServiceDetailCaptureScope => 'Erfassungsumfang';

  @override
  String get pluginServiceDetailCredentialPolicy => 'Anmeldedatenschutz';

  @override
  String get pluginServiceDetailSessionCleanup => 'Sitzungsbereinigung';

  @override
  String get pluginServiceDetailUpdatePolicy => 'Aktualisierungsstrategie';

  @override
  String get pluginServiceDetailUninstallPolicy => 'Deinstallationsstrategie';

  @override
  String get pluginServiceDetailOfficialSite => 'Offizielle Website';

  @override
  String pluginServiceMcpInstalledVersion(Object version) {
    return 'Installiert v$version';
  }

  @override
  String get pluginServiceMcpOperationTimeout =>
      '[timeout] Vorgang hat zu lange gedauert; Prozess beendet';

  @override
  String pluginServiceMcpOperationCompleted(Object action, Object exitCode) {
    return '✓ $action abgeschlossen (exit code: $exitCode)';
  }

  @override
  String pluginServiceMcpOperationFailed(Object action, Object exitCode) {
    return '✗ $action fehlgeschlagen (exit code: $exitCode)';
  }

  @override
  String pluginServiceMcpOperationError(Object error) {
    return '✗ Fehler: $error';
  }

  @override
  String get pluginServiceMcpVerificationFailed =>
      'Die MCP-Statusprüfung nach dem Vorgang ist fehlgeschlagen';

  @override
  String get pluginServiceDescriptionNodejs =>
      'JavaScript-Laufzeit für JS/TS-Skripte und Toolchains';

  @override
  String get pluginServiceDescriptionPlaywright =>
      'Framework für Browser-Automatisierungstests mit Chromium, Firefox und WebKit';

  @override
  String get pluginServiceDescriptionPython =>
      'Python-Laufzeit für Skripte, Bibliotheken und Erweiterungen';

  @override
  String get pluginServiceDescriptionPip =>
      'Python-Paketmanager zum Installieren, Aktualisieren und Verwalten von Bibliotheken';

  @override
  String get pluginServiceDescriptionJava =>
      'JDK-Laufzeit für Android-Static-Analysis-Tools wie apktool und jadx';

  @override
  String get pluginServiceDescriptionFrida =>
      'Dynamische Instrumentierungs- und Hook-Toolchain für Android-Laufzeitvalidierung';

  @override
  String get pluginServiceDescriptionMitmproxy =>
      'HTTP(S)-Proxy-Capture-Tool für Web- und Android-Traffic-Forensik';

  @override
  String get pluginServiceDescriptionApktool =>
      'Tool zum Entpacken von APKs und zur smali-Analyse';

  @override
  String get pluginServiceDescriptionJadx => 'DEX-/APK-Java-Decompiler';

  @override
  String get pluginServiceDescriptionRadare2 =>
      'Tool für binäre statische Analyse und ELF-/native-so-Reverse-Engineering';

  @override
  String get pluginServiceDescriptionBlutter =>
      'Flutter-Dart-AOT-Recovery-Tool für libapp.so-Analysen';

  @override
  String get pluginServiceDescriptionDoldrums =>
      'Hilfstool für Flutter-snapshot-/ELF-Analysen';

  @override
  String get pluginServiceDescriptionAnythingAnalyzer =>
      'Protokollanalyse- und MCP-Server-Tool für Capture, Analyse und Agent-Integration';

  @override
  String get pluginServiceDescriptionDocker =>
      'Container-Laufzeit für den lokalen Qdrant-Vektordatenbankdienst';

  @override
  String get pluginServiceDescriptionQdrant =>
      'Lokale Vektordatenbank für Knowledge-Base-Embedding-Indizes und Retrieval';

  @override
  String get pluginServiceDescriptionPostgresql =>
      '关系型数据库服务，供 AI 暴露面扫描保存任务与审计数据';

  @override
  String get pluginServiceDescriptionRedis => '内存数据存储服务，供 AI 暴露面扫描执行缓存与任务队列';

  @override
  String get pluginServiceDescriptionDingtalkWorkspaceCli =>
      'DingTalk Workspace CLI für AI-Agent-Workflows in DingTalk';

  @override
  String get pluginServiceDescriptionGoogleChrome =>
      'Lokale Chrome-Laufzeit für native CDP-Seiten- und Netzwerkerfassung bei Forumssuchen';

  @override
  String get pluginServiceDetailExternalService => '外部服务';

  @override
  String get pluginServiceDetailServiceRunning => '服务运行中';

  @override
  String get pluginServiceDetailEndpoint => '服务端点';

  @override
  String get pluginServiceTemplateWebReverseExpert => 'Web Reverse Expert';

  @override
  String get pluginServiceTemplateAndroidReverseExpert =>
      'Android Reverse Expert';

  @override
  String get pluginServiceTemplateHermesTalker => 'Hermes Talker';

  @override
  String get mcpStdioMirrorModeLabel => 'Mirror-Registry-Modus';

  @override
  String get mcpStdioMirrorModeBody =>
      'Beim Cold Start von stdio-MCP-Diensten: China-Mirror (npmmirror / Tsinghua PyPI) injizieren? auto = nach Systemsprache. Erzwingen ein/aus = Locale ignorieren. OPENHAND_MCP_MIRROR=on/off überschreibt zur Laufzeit.';

  @override
  String get mcpStdioMirrorModeAuto => 'Sprachbasiert';

  @override
  String get mcpStdioMirrorModeForceOn => 'Erzwingen ein';

  @override
  String get mcpStdioMirrorModeForceOff => 'Erzwingen aus';

  @override
  String get mcpStdioMirrorModeStatusInjected =>
      'Aktiv: npmmirror / Tsinghua PyPI werden injiziert';

  @override
  String get mcpStdioMirrorModeStatusBypassed =>
      'Aktiv: offizielles Registry, kein Mirror';

  @override
  String mcpStdioMirrorModeStatusReason(Object reason) {
    return 'Quelle: $reason';
  }

  @override
  String get mcpStdioMirrorModeReasonEnv =>
      'Umgebungsvariable OPENHAND_MCP_MIRROR';

  @override
  String get mcpStdioMirrorModeReasonSetting => 'Einstellung erzwungen';

  @override
  String mcpStdioMirrorModeReasonLocale(Object locale) {
    return 'Systemsprache ($locale)';
  }

  @override
  String get mcpStdioMirrorModeReconnectAction =>
      'Aktivierte Server mit neuer Einstellung neu verbinden';

  @override
  String get mcpStdioMirrorModeReconnectDone =>
      'Reconnect ausgelöst. Beim nächsten Aufruf wird der Prozess mit dem neuen Mirror neu gestartet.';

  @override
  String mcpStdioDialogLogsTitle(Object name) {
    return '$name-Logs';
  }

  @override
  String mcpStdioDialogRuntimeDetailsTitle(Object name) {
    return '$name-Runtime-Details';
  }

  @override
  String mcpStdioDialogRunningPid(Object pid) {
    return 'Läuft · PID $pid';
  }

  @override
  String get mcpStdioDialogStopped => 'Gestoppt';

  @override
  String get mcpStdioDialogAutoScroll => 'Automatisch scrollen';

  @override
  String get mcpStdioDialogCopyLogs => 'Logs kopieren';

  @override
  String get mcpStdioDialogClearLogs => 'Logs leeren';

  @override
  String get mcpStdioDialogCopiedToClipboard => 'In die Zwischenablage kopiert';

  @override
  String get mcpStdioDialogNoLogOutput => 'Noch keine Log-Ausgabe';

  @override
  String mcpStdioDialogLineCount(int count) {
    return '$count Zeilen';
  }

  @override
  String mcpStdioDialogUptime(Object uptime) {
    return 'Läuft seit $uptime';
  }

  @override
  String get mcpStdioDialogRefresh => 'Aktualisieren';

  @override
  String get settingsScraplingRuntimeActionInstall => 'Installieren';

  @override
  String get settingsScraplingRuntimeActionUninstall => 'Deinstallieren';

  @override
  String settingsScraplingRuntimeCommand(Object action) {
    return '$action Scrapling-Laufzeit';
  }

  @override
  String get settingsScraplingRuntimeInstallTitle =>
      'Scrapling-Laufzeit installieren';

  @override
  String get settingsScraplingRuntimeUninstallTitle =>
      'Scrapling-Laufzeit deinstallieren';

  @override
  String get settingsScraplingRuntimeInstalling => 'Installation läuft…';

  @override
  String get settingsScraplingRuntimeUninstalling => 'Deinstallation läuft…';

  @override
  String get settingsScraplingRuntimeInstalled => 'Installiert';

  @override
  String get settingsScraplingRuntimeUninstalled => 'Deinstalliert';

  @override
  String get settingsScraplingRuntimeFailed => 'Fehlgeschlagen';

  @override
  String get settingsScraplingRuntimeCertificateDiagnosis =>
      'Diagnose: Python / pip in der aktuellen Umgebung kann die PyPI-Zertifikatskette nicht validieren. Prüfe die CA-Zertifikate des Systems, Proxy-Abfangzertifikate oder konfiguriere eine gültige Zertifikatsdatei für Python.';

  @override
  String get settingsScraplingRuntimeCopiedAllLogs => 'Alle Protokolle kopiert';

  @override
  String get settingsScraplingRuntimeCopyLogs => 'Protokolle kopieren';

  @override
  String get mcpStdioDialogProcessStatus => 'Prozessstatus';

  @override
  String get mcpStdioDialogServiceConfig => 'Dienstkonfiguration';

  @override
  String get mcpStdioDialogType => 'Typ';

  @override
  String get mcpStdioDialogCommand => 'Befehl';

  @override
  String get mcpStdioDialogArgs => 'Argumente';

  @override
  String get mcpStdioDialogEnabled => 'Aktiviert';

  @override
  String get mcpStdioDialogYes => 'Ja';

  @override
  String get mcpStdioDialogNo => 'Nein';

  @override
  String get mcpStdioDialogEnvironment => 'Umgebung';

  @override
  String get mcpStdioDialogError => 'Fehler';

  @override
  String get mcpStdioDialogDepsTitle => 'Abhängigkeitsverwaltung';

  @override
  String get mcpStdioDialogNoDepsToManage =>
      'Dieser Dienst basiert nicht auf einem Paketmanager (npx / uvx). Keine Abhängigkeiten zu verwalten.';

  @override
  String mcpStdioDialogInstalledVersion(Object version) {
    return 'Installiert v$version';
  }

  @override
  String get mcpStdioDialogUnknownVersion => '?';

  @override
  String get mcpStdioDialogNotGloballyInstalled => 'Nicht global installiert';

  @override
  String get mcpStdioDialogInstall => 'Installieren';

  @override
  String get mcpStdioDialogUpdate => 'Aktualisieren';

  @override
  String get mcpStdioDialogUninstall => 'Deinstallieren';

  @override
  String mcpStdioDialogLatestVersion(Object version) {
    return 'Neueste Version: $version';
  }

  @override
  String get mcpStdioDialogUpdateAvailableSuffix => ' (Update verfügbar)';

  @override
  String get mcpStdioDialogOperationTimeout =>
      '[timeout] Vorgang überschritten; Prozess beendet';

  @override
  String mcpStdioDialogOperationCompleted(
    Object time,
    Object action,
    int exitCode,
  ) {
    return '[$time] ✓ $action abgeschlossen (Exit-Code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationFailed(
    Object time,
    Object action,
    int exitCode,
  ) {
    return '[$time] ✗ $action fehlgeschlagen (Exit-Code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationFailedPlain(Object action, int exitCode) {
    return '$action fehlgeschlagen (Exit-Code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationException(Object time, Object error) {
    return '[$time] ✗ Ausnahme: $error';
  }

  @override
  String mcpStdioDialogWarmCache(Object time) {
    return '[$time] Isolierten Cache vorwärmen…';
  }

  @override
  String mcpStdioDialogWarmCacheDone(Object time) {
    return '[$time] ✓ Cache vorgewärmt';
  }

  @override
  String mcpStdioDialogWarmCacheSkipped(Object time, Object error) {
    return '[$time] Cache-Vorwärmen übersprungen: $error';
  }

  @override
  String get mcpAutoProbeConcurrencyLabel => 'MCP Check/Fetch Parallelität';

  @override
  String get mcpAutoProbeConcurrencyBody =>
      'Maximale Anzahl von MCP-Diensten, die parallel geprüft oder abgefragt werden. Standard 5; niedriger reduziert Ressourcenlast, höher beschleunigt viele Dienste.';

  @override
  String get mcpAutoProbeConcurrencySave => 'Parallelität speichern';

  @override
  String get mcpAutoProbeConcurrencySaved =>
      'MCP Check/Fetch Parallelität gespeichert.';

  @override
  String get mcpAutoProbeConcurrencyInvalid =>
      'Bitte eine ganze Zahl zwischen 1 und 32 eingeben.';

  @override
  String get mcpProbeDetailsTitle => 'MCP-Prüfdetails';

  @override
  String get mcpProbePoolActive => 'Prüfpool aktiv';

  @override
  String get mcpProbePoolIdle => 'Prüfpool inaktiv';

  @override
  String get mcpProbePoolStatusTitle => 'Pool-Status';

  @override
  String mcpProbeSlots(int active, int total) {
    return 'Slots $active/$total';
  }

  @override
  String mcpProbeQueued(int count) {
    return 'Wartend $count';
  }

  @override
  String get mcpProbeStateRunning => 'läuft';

  @override
  String get mcpProbeStateIdle => 'inaktiv';

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
    return 'Letzte $time';
  }

  @override
  String mcpProbeNextRun(Object time) {
    return 'Nächste $time';
  }

  @override
  String get mcpProbeControlsTitle => 'Prüfsteuerung';

  @override
  String get mcpProbeForceProbe => 'Prüfung erzwingen';

  @override
  String get mcpProbeStopProbing => 'Prüfung stoppen';

  @override
  String get mcpProbeReloadServers => 'Serverliste neu laden';

  @override
  String mcpProbeServerStatusTitle(int count) {
    return 'Server-Prüfstatus ($count Server)';
  }

  @override
  String get mcpProbeNoServers => 'Keine Server';

  @override
  String get mcpProbeHealthHealthy => 'Gesund';

  @override
  String get mcpProbeHealthUnhealthy => 'Fehlerhaft';

  @override
  String get mcpProbeHealthChecking => 'Prüft';

  @override
  String get mcpProbeHealthIdle => 'Bereit';

  @override
  String get mcpProbeDisableServerTooltip => 'Prüfung deaktivieren';

  @override
  String get mcpProbeEnableServerTooltip => 'Prüfung aktivieren';

  @override
  String get mcpProbeNoProbe => 'Keine Prüfung';

  @override
  String mcpProbeToolCount(int count) {
    return '$count Tools';
  }

  @override
  String get mcpProbeThisServer => 'Diesen Server prüfen';

  @override
  String get mcpRelativeJustNow => 'gerade eben';

  @override
  String mcpRelativeSecondsAgo(int seconds) {
    return 'vor ${seconds}s';
  }

  @override
  String mcpRelativeMinutesAgo(int minutes) {
    return 'vor ${minutes}m';
  }

  @override
  String mcpRelativeHoursAgo(int hours) {
    return 'vor ${hours}h';
  }

  @override
  String mcpRelativeDaysAgo(int days) {
    return 'vor ${days}d';
  }

  @override
  String get mcpRelativeImminent => 'gleich';

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
  String get mcpKeywordIndexUpdateModeLabel =>
      'Aktualisierungsmodus für Keyword-Index';

  @override
  String get mcpKeywordIndexUpdateModeBody =>
      'Steuert, wie der invertierte Keyword-Index der MCP-Tools neu aufgebaut wird. Kaltstart: nur beim Boot vom Datenträger laden; Aktualisierung über die Schaltfläche „Keyword-Index erstellen“. Intervall: zyklisch (Wert + Einheit) neu aufbauen und Cache vollständig überschreiben. Tageszeit: einmal täglich zur festgelegten Zeit. Die letzten beiden teilen sich einen System-Cron-Eintrag, um eine Fragmentierung zu vermeiden.';

  @override
  String get mcpKeywordIndexUpdateModeColdStart => 'Kaltstart';

  @override
  String get mcpKeywordIndexUpdateModeInterval => 'Intervall';

  @override
  String get mcpKeywordIndexUpdateModeScheduled => 'Tageszeit';

  @override
  String get mcpKeywordIndexUpdateModeColdStartHint =>
      'Kaltstart-Modus: lädt den Keyword-Index nur beim App-Start vom Datenträger; zum Aktualisieren auf „Keyword-Index erstellen“ klicken. Der System-Cron-Eintrag bleibt deaktiviert.';

  @override
  String get mcpKeywordIndexIntervalValueLabel => 'Intervall';

  @override
  String get mcpKeywordIndexIntervalUnitLabel => 'Einheit';

  @override
  String get mcpKeywordIndexIntervalUnitMinute => 'Minute(n)';

  @override
  String get mcpKeywordIndexIntervalUnitHour => 'Stunde(n)';

  @override
  String get mcpKeywordIndexIntervalUnitDay => 'Tag(e)';

  @override
  String mcpKeywordIndexScheduledLabel(String time) {
    return 'Täglich um $time neu erstellen';
  }

  @override
  String get mcpKeywordIndexScheduledPickAction => 'Zeit wählen';

  @override
  String get commonClose => 'Schließen';

  @override
  String get commonRunInBackground => 'Im Hintergrund ausführen';

  @override
  String get mcpBuildKeywordIndex => 'Stichwortindex erstellen';

  @override
  String get mcpKeywordIndexBuildTitle => 'Stichwort-Invertindex wird erstellt';

  @override
  String get mcpKeywordIndexBuildStarting => 'Vorbereitung…';

  @override
  String mcpKeywordIndexBuildProgress(
    int idx,
    int count,
    Object server,
    int tools,
  ) {
    return '$idx/$count: $server ($tools Tools gescannt)';
  }

  @override
  String mcpKeywordIndexBuildSummary(
    int servers,
    int tools,
    int keys,
    Object sec,
  ) {
    return 'Indexiert: $servers Server, $tools Tools, $keys Stichwörter in ${sec}s';
  }

  @override
  String mcpKeywordIndexBuildSkipped(int n) {
    return '$n Server ohne bereiten Katalog übersprungen';
  }

  @override
  String get mcpKeywordIndexBuildFailed => 'Erstellung fehlgeschlagen:';

  @override
  String get mcpLazyLoadingModeLabel => 'MCP-Tool Lazy Loading';

  @override
  String get mcpLazyLoadingModeBody =>
      'Legt fest, ob MCP-Tool-Beschreibungen aus dem System-Prompt ausgelagert werden: Aus = immer geladen; Ein = immer ausgelagert und bei Bedarf via ToolSearch geholt; Auto lagert nur aus, wenn die geschätzten Tokens den Schwellenwert überschreiten.';

  @override
  String get mcpLazyLoadingModeDisabled => 'Aus';

  @override
  String get mcpLazyLoadingModeAuto => 'Auto';

  @override
  String get mcpLazyLoadingModeEnabled => 'Ein';

  @override
  String get mcpLazyLoadingThresholdLabel => 'MCP-Tool-Kompressionsschwelle';

  @override
  String get mcpLazyLoadingThresholdBody =>
      'Im Auto-Modus wird Lazy Loading aktiviert, sobald die geschätzten Gesamttokens der MCP-Tool-Beschreibungen diesen Wert überschreiten.';

  @override
  String get mcpLazyLoadingThresholdSave => 'Schwelle speichern';

  @override
  String get mcpLazyLoadingThresholdSaved =>
      'MCP-Lazy-Loading-Schwelle gespeichert.';

  @override
  String get mcpLazyLoadingThresholdInvalid =>
      'Bitte eine Ganzzahl zwischen 1000 und 1000000 eingeben.';

  @override
  String get settingsHarnessToolSearchHistoryCapLabel =>
      'Harness ToolSearch Verlaufslimit';

  @override
  String get settingsHarnessToolSearchHistoryCapBody =>
      'Maximale Anzahl letzter Harness-Phasen, für die der ToolSearch-Verlauf im Dialog „Geladene Liste“ gespeichert bleibt. Ältere Phasen werden per LRU verworfen.';

  @override
  String settingsHarnessToolSearchHistoryCapValue(int cap) {
    return 'Zurzeit werden die letzten $cap Phase(n) gespeichert';
  }

  @override
  String settingsHarnessToolSearchHistoryCapRange(int min, int max) {
    return 'Bereich: $min–$max (Standard 8)';
  }

  @override
  String settingsHarnessToolSearchHistoryCapResetTooltip(int defaultCap) {
    return 'Auf Standard zurücksetzen ($defaultCap)';
  }

  @override
  String get harnessCliLoginNoOutputHint =>
      '[Hinweis] Die CLI hat noch keine Ausgabe erzeugt. Sie initialisiert möglicherweise noch oder wartet auf eine Autorisierung im Browser.\n';

  @override
  String harnessCliLoginTimedOut(int minutes) {
    return 'Die Anmeldung wurde nach $minutes Minuten wegen Zeitüberschreitung beendet. Der Prozess wurde gestoppt.';
  }

  @override
  String get harnessCliLoginTtyRequiredHint =>
      '[Hinweis] Diese CLI benötigt für die interaktive Anmeldung möglicherweise ein echtes Terminal (TTY).\nVerwende unten „Im Terminal öffnen“, um die Anmeldung im Systemterminal abzuschließen.\n';

  @override
  String harnessCliLoginStreamError(Object error) {
    return '[Stream-Fehler: $error]';
  }

  @override
  String harnessCliLoginFailedToStartProcess(Object message) {
    return 'Prozess konnte nicht gestartet werden: $message';
  }

  @override
  String harnessCliLoginOpenTerminalError(Object error) {
    return '[Fehler beim Öffnen des Terminals: $error]';
  }

  @override
  String get harnessCliLoginStatusFailed => 'Start fehlgeschlagen';

  @override
  String get harnessCliLoginStatusStarting =>
      'Anmeldevorgang wird gestartet...';

  @override
  String get harnessCliLoginStatusFinished => 'Prozess beendet';

  @override
  String harnessCliLoginStatusFinishedWithExit(int exitCode) {
    return 'Prozess beendet · Exit $exitCode';
  }

  @override
  String get harnessCliLoginStatusWaiting => 'Warte auf CLI-Interaktion...';

  @override
  String harnessCliLoginTitle(Object name) {
    return '$name-Anmeldung';
  }

  @override
  String get harnessCliLoginDescription =>
      'Dieser Dialog führt die CLI-Anmeldung in der App aus. Die CLI kann während der Authentifizierung extern deinen Browser öffnen.';

  @override
  String get harnessCliLoginCopyCommandTooltip => 'Befehl kopieren';

  @override
  String get harnessCliLoginEmptyOutput => 'Warte auf CLI-Ausgabe...';

  @override
  String get harnessCliLoginInputLabel => 'Eingabe senden';

  @override
  String get harnessCliLoginInputHint =>
      'Antwort eingeben und Enter drücken; leer lassen, um Enter zu senden';

  @override
  String get harnessCliLoginSend => 'Senden';

  @override
  String get harnessCliLoginSendEsc => 'Esc senden';

  @override
  String get harnessCliLoginOpenInTerminal => 'Im Terminal öffnen';

  @override
  String get harnessCliInstallLogSuccess => '✓ Installation erfolgreich';

  @override
  String harnessCliInstallLogSuccessWithPath(Object path) {
    return '✓ Installation erfolgreich (Pfad: $path)';
  }

  @override
  String harnessCliInstallLogFailureExitCode(int exitCode) {
    return '✗ Installation fehlgeschlagen (Exit-Code: $exitCode)';
  }

  @override
  String harnessCliInstallLogStartProcessFailed(Object message) {
    return '✗ Installationsprozess konnte nicht gestartet werden: $message';
  }

  @override
  String harnessCliInstallLogGenericError(Object error) {
    return '✗ Fehler: $error';
  }

  @override
  String get harnessCliInstallHintInstallNode =>
      '  → Installiere zuerst Node.js: https://nodejs.org';

  @override
  String get harnessCliInstallHintRetryAdminButton =>
      '  → Klicke unten auf „Mit Adminrechten erneut versuchen“';

  @override
  String harnessCliInstallHintTrySudo(Object command) {
    return '  → Versuche: sudo $command';
  }

  @override
  String get harnessCliInstallHintCheckNetworkDocs =>
      '  → Prüfe die Netzwerkverbindung oder lies die offizielle Dokumentation';

  @override
  String get harnessCliInstallHintInstallPipx =>
      '  → Installiere zuerst pipx: https://pipx.pypa.io/stable/installation/';

  @override
  String get harnessCliInstallHintUsePipInstallUserAider =>
      '    Oder verwende: pip install --user aider-chat';

  @override
  String get harnessCliInstallHintHomebrewNoSudo =>
      '  → Homebrew sollte normalerweise nicht mit sudo installiert werden; prüfe die Ordnerrechte';

  @override
  String get harnessCliInstallHintHomebrewFix =>
      '  → Empfohlene Lösung: https://docs.brew.sh/FAQ#why-does-homebrew-say-sudo-is-not-allowed';

  @override
  String get harnessCliInstallHintInstallPython =>
      '  → Installiere zuerst Python: https://www.python.org';

  @override
  String harnessCliInstallHintPipInstallUser(Object packageName) {
    return '  → Versuche: pip install --user $packageName';
  }

  @override
  String harnessCliInstallHintOfficialDocs(Object url) {
    return '  → Offizielle Dokumentation: $url';
  }

  @override
  String get harnessCliInstallLogCancelled =>
      '⚠ Installation wurde abgebrochen';

  @override
  String get harnessCliInstallWindowsAdminManual =>
      'Manuell in PowerShell mit Administratorrechten ausführen:';

  @override
  String harnessCliInstallAdminCommand(Object command) {
    return '> [Admin] $command';
  }

  @override
  String get harnessCliInstallAdminTimeout =>
      '✗ Der Admin-Autorisierungsdialog ist abgelaufen oder konnte nicht gestartet werden; der osascript-Unterprozess wurde beendet';

  @override
  String get harnessCliInstallUserCancelledAuth =>
      '⚠ Autorisierung wurde abgebrochen';

  @override
  String get harnessCliInstallAdminPermissionFailed =>
      '✗ Administratorrechte konnten nicht abgerufen werden';

  @override
  String harnessCliInstallPathMissingWarning(Object executable) {
    return '⚠ Installation abgeschlossen, aber $executable wurde im aktuellen PATH nicht gefunden';
  }

  @override
  String get harnessCliInstallRestartPathHint =>
      '  → Starte OpenHand neu oder öffne es aus einem Terminal, um den neuen PATH zu laden';

  @override
  String get harnessCliInstallTimeoutManual =>
      '✗ Installation überschritten (mehr als 5 Minuten). Manuell ausführen:';

  @override
  String harnessCliInstallOsascriptStartFailed(Object message) {
    return '✗ osascript konnte nicht gestartet werden: $message';
  }

  @override
  String get harnessCliInstallLinuxSudoManual =>
      'Manuell in einem Terminal ausführen (root-Rechte erforderlich):';

  @override
  String get harnessCliInstallStatusInstalling => 'Installation läuft...';

  @override
  String get harnessCliInstallStatusSuccess => 'Installation erfolgreich';

  @override
  String get harnessCliInstallStatusCancelled => 'Abgebrochen';

  @override
  String get harnessCliInstallStatusFailed => 'Installation fehlgeschlagen';

  @override
  String harnessCliInstallTitle(Object name) {
    return '$name installieren';
  }

  @override
  String get harnessCliInstallCopyDocUrl => 'Doku-URL kopieren';

  @override
  String get harnessCliInstallCancel => 'Installation abbrechen';

  @override
  String get harnessCliInstallRetryAdmin => 'Mit Adminrechten erneut versuchen';

  @override
  String get harnessCliInstallDoneContinue => 'Fertig, weiter';

  @override
  String get settingsToolSearchReplayCancelWindowLabel =>
      'Wiedergabe-Abbruchfenster';

  @override
  String get settingsToolSearchReplayCancelWindowBody =>
      'Wartezeit der Snackbar vor dem Senden; innerhalb des Fensters kann mit Abbrechen verworfen werden.';

  @override
  String settingsToolSearchReplayCancelWindowValue(int seconds) {
    return 'Fenster: $seconds s';
  }

  @override
  String settingsToolSearchReplayCancelWindowRange(int min, int max) {
    return 'Bereich: $min–$max s (Standard 3)';
  }

  @override
  String settingsToolSearchReplayCancelWindowResetTooltip(int defaultSeconds) {
    return 'Auf Standard zurücksetzen ($defaultSeconds s)';
  }

  @override
  String get mcpLazyLoadingHowItWorks =>
      'Bei aktivem Lazy Loading werden MCP-Tool-Beschreibungen zu einem Namensindex zusammengefaltet. Das eingebaute ToolSearch-Tool ruft das vollständige JSON-Schema bei Bedarf über drei Abfrageformen ab:\n• select:NAME (direkte Auswahl, mehrfach durch Leerzeichen getrennt)\n• Stichwort (bewertet gegen name/description)\n• +STICHWORT (Pflichtwort zum Filtern)\nNach einem Treffer wird ToolSearch mit dem exakten tool_name und schema-konformen arguments aufgerufen. Die native Tool-Liste bleibt für den Prompt-Cache unverändert.';

  @override
  String get settingsGeneralSubtitle =>
      'Verwalte Thema, Sprache und grundlegende App-Informationen.';

  @override
  String get settingsAiSubtitle =>
      'Chat-Modelle, Authentifizierung und Protokolladapter verwalten.';

  @override
  String get settingsActiveToolCallsTitle => 'Aktive Tool-Aufrufe';

  @override
  String get settingsActiveToolCallsBody =>
      'Live-Ansicht aller ausgeführten Tool-Aufrufe: PID, Art, zugehörige Sitzung und Laufzeit. Mit Stop nur diesen Aufruf abbrechen.';

  @override
  String get settingsActiveToolCallsEmpty =>
      'Aktuell laufen keine Tool-Aufrufe.';

  @override
  String get settingsActiveToolCallsCancel => 'Stoppen';

  @override
  String get settingsActiveToolKindBuiltin => 'Integriert';

  @override
  String get settingsActiveToolKindMcp => 'MCP';

  @override
  String get settingsActiveToolKindSkill => 'Skill';

  @override
  String get settingsActiveToolSessionLabel => 'Sitzung';

  @override
  String get settingsToolHardeningTitle => 'Tool-Härtungsparameter';

  @override
  String get settingsToolHardeningBody =>
      'Graceful-Shutdown-Dauer für Subprozesse, Bash-Ausgabelimit und Limit paralleler Toolaufrufe.';

  @override
  String get settingsSubprocessGracefulShutdownLabel =>
      'Subprozess Graceful Shutdown (ms)';

  @override
  String get settingsSubprocessGracefulShutdownBody =>
      'Wartezeit zwischen SIGTERM und SIGKILL beim Abbruch. Größere Werte sind sanfter, lassen Stop aber langsamer wirken. Bereich 100–5000.';

  @override
  String get settingsBashOutputMaxBytesLabel =>
      'Bash-Erfassungsgrenze (Zeichen)';

  @override
  String get settingsBashOutputMaxBytesBody =>
      'Obergrenze für kombinierte stdout+stderr-Erfassung pro Aufruf. Überschüssige Ausgabe wird mittig gekürzt. Bereich 16000–4000000.';

  @override
  String get settingsMaxConcurrentToolsLabel => 'Parallele Tool-Aufrufe';

  @override
  String get settingsMaxConcurrentToolsBody =>
      'Maximale gleichzeitig ausgeführte Tool-Aufrufe pro Sitzung. Bereich 1–64.';

  @override
  String get settingsToolHardeningInvalid =>
      'Bitte ganze Zahl im Bereich eingeben';

  @override
  String get settingsSkillsSubtitle =>
      'Verwalte das lokale Skill-Verzeichnis, Vorlagen und installierte Skills.';

  @override
  String get settingsMemorySubtitle =>
      'Schalter für Nutzer-Speicher und Persistenz-Dateipfad verwalten.';

  @override
  String get settingsPersistenceInvalidTitle =>
      'Einstellungsdaten sind ungültig';

  @override
  String get settingsPersistenceInvalidBody =>
      'Der Datenbankeintrag kann nicht gelesen werden. Standardwerte werden angezeigt, ohne die Originaldaten zu überschreiben.';

  @override
  String get settingsPersistenceLoadFailedTitle =>
      'Einstellungen konnten nicht gelesen werden';

  @override
  String get settingsPersistenceLoadFailedBody =>
      'Die lokale Datenbank ist nicht lesbar. Standardwerte werden vorübergehend angezeigt und das Speichern wird pausiert.';

  @override
  String get settingsPersistenceSaveFailedTitle =>
      'Speichern der Einstellungen fehlgeschlagen';

  @override
  String get settingsPersistenceSaveFailedBody =>
      'Das Schreiben in die Einstellungsdatenbank ist fehlgeschlagen. Die Oberfläche wurde zurückgesetzt. Datenbankzugriff und Festplattenzustand prüfen.';

  @override
  String get settingsPersistenceDismiss => 'Schließen';

  @override
  String get settingsAnimationRestoreDefaultsTitle =>
      'Animationsvorgaben wiederherstellen';

  @override
  String get settingsAnimationRestoreDefaultsSubtitle =>
      'Setzt Eingangs-/Ausgangsstil, Dauer und Kurve für Dialoge, Menüs, Seiten/Module, Arbeitsbereichspanels, Chips und Listenelemente auf die empfohlenen OpenHand-Standardwerte zurück.';

  @override
  String get settingsAnimationRestoreDefaultsButton =>
      'Standard wiederherstellen';

  @override
  String get settingsAnimationRestoreConfirmTitle =>
      'Standardanimationen wiederherstellen?';

  @override
  String get settingsAnimationRestoreConfirmMessage =>
      'Alle Animationen für Dialoge, Menüs, Seiten/Module, Arbeitsbereichspanels, Chips und Listenelemente werden zurückgesetzt. Eigene Werte werden überschrieben.';

  @override
  String get settingsAnimationRestoreConfirm => 'Wiederherstellen';

  @override
  String get settingsAnimationRestoreSuccess =>
      'Animationsvorgaben wiederhergestellt';

  @override
  String get settingsDialogAnimationTitle => 'Dialoganimation';

  @override
  String get settingsDialogAnimationSubtitle =>
      'Eingangs-/Ausgangsstil, Dauer und Kurve für alle Dialoge konfigurieren.';

  @override
  String get settingsMenuAnimationTitle => 'Menüanimation';

  @override
  String get settingsMenuAnimationSubtitle =>
      'Eingangs-/Ausgangsstil, Dauer und Kurve für Popup-, Kontext- und Dropdown-Menüs konfigurieren.';

  @override
  String get settingsPanelAnimationTitle => 'Arbeitsbereichspanel-Animation';

  @override
  String get settingsPanelAnimationSubtitle =>
      'Übergänge der Arbeitsbereichspanels konfigurieren, etwa Navigation/Dateien links und Unterhaltung/Editor rechts. Rechte Module nutzen die Seitenanimation.';

  @override
  String get settingsPageAnimationTitle => 'Seiten-/Modulanimation';

  @override
  String get settingsPageAnimationSubtitle =>
      'Übergänge des rechten Hauptinhalts konfigurieren, einschließlich Workspace, Einstellungen, MCP, Speicher, Hooks, Crons, Skills und Automatisierungen.';

  @override
  String get settingsChipAnimationTitle => 'Chip-Animation';

  @override
  String get settingsChipAnimationSubtitle =>
      'Eingangs-/Ausgangsanimationen für entfernbare Chips konfigurieren: ausgewählte Skills, Anhänge, Projektreferenzen, Warteschlangen-Nachrichten, Bearbeitungspille usw.';

  @override
  String get settingsListItemAnimationTitle => 'Listenelement-Animation';

  @override
  String get settingsListItemAnimationSubtitle =>
      'Eingangsanimationen für Listenelemente wie MCP-Server, Speichereinträge, Anweisungskarten, Sidebar-Threads und Toolaufruf-Karten konfigurieren.';

  @override
  String get settingsAnimationEnter => 'Eintritt';

  @override
  String get settingsAnimationExit => 'Austritt';

  @override
  String get settingsAnimationDuration => 'Dauer';

  @override
  String get settingsAnimationCurve => 'Kurve';

  @override
  String get dialogAnimationStyleNone => 'Keine';

  @override
  String get dialogAnimationStyleFade => 'Fade';

  @override
  String get dialogAnimationStyleFadeScale => 'Fade & Skalierung';

  @override
  String get dialogAnimationStyleSlideUp => 'Nach oben gleiten';

  @override
  String get dialogAnimationStyleSlideDown => 'Nach unten gleiten';

  @override
  String get dialogAnimationStyleSlideLeft => 'Nach links gleiten';

  @override
  String get dialogAnimationStyleSlideRight => 'Nach rechts gleiten';

  @override
  String get dialogAnimationStyleExpand => 'Expandieren';

  @override
  String get dialogAnimationStyleRotateScale => 'Drehen & Skalieren';

  @override
  String get dialogAnimationStyleElastic => 'Elastisch';

  @override
  String get dialogAnimationStyleSpringScale => 'Feder-Skalierung';

  @override
  String get dialogAnimationStyleFlipX => 'Flip X';

  @override
  String get dialogAnimationCurveEaseInOut => 'Ease In-Out';

  @override
  String get dialogAnimationCurveEaseOut => 'Ease Out';

  @override
  String get dialogAnimationCurveEaseOutCubic => 'Ease Out Cubic';

  @override
  String get dialogAnimationCurveEaseInOutCubicEmphasized => 'Cubic betont';

  @override
  String get dialogAnimationCurveElasticOut => 'Elastic Out';

  @override
  String get dialogAnimationCurveBounceOut => 'Bounce Out';

  @override
  String get dialogAnimationCurveDecelerate => 'Verlangsamen';

  @override
  String get commonOptional => 'Optional';

  @override
  String get cronScriptTypeCommand => 'Befehl';

  @override
  String get cronScriptTypeScript => 'Skript';

  @override
  String get cronScriptTypeManaged => 'Systemverwaltet';

  @override
  String get cronJobStatusRunning => 'Laeuft';

  @override
  String get cronJobStatusPaused => 'Pausiert';

  @override
  String get cronJobStatusFailed => 'Fehlgeschlagen';

  @override
  String get cronJobStatusError => 'Fehler';

  @override
  String get cronJobStatusIdle => 'Leerlauf';

  @override
  String get cronNotifyTypeNone => 'Keine';

  @override
  String get cronNotifyTypeLog => 'Nur Log';

  @override
  String get cronNotifyTypeSystem => 'Systembenachrichtigung';

  @override
  String get cronNotifyTypeAppNotification => 'In-App-Benachrichtigung';

  @override
  String get cronNotifySeverityInfo => 'Info';

  @override
  String get cronNotifySeveritySuccess => 'Erfolg';

  @override
  String get cronNotifySeverityWarning => 'Warnung';

  @override
  String get cronNotifySeverityError => 'Fehler';

  @override
  String get cronNotifySeverityCritical => 'Kritisch';

  @override
  String get cronParserFieldCountError =>
      'Der Cron-Ausdruck muss genau 5 Felder haben (Min Stunde Tag Monat Wochentag)';

  @override
  String get cronParserFieldMinute => 'Minute';

  @override
  String get cronParserFieldHour => 'Stunde';

  @override
  String get cronParserFieldDayOfMonth => 'Monatstag';

  @override
  String get cronParserFieldDayOfMonthShort => 'Tag';

  @override
  String get cronParserFieldMonth => 'Monat';

  @override
  String get cronParserFieldDayOfWeek => 'Wochentag';

  @override
  String get cronParserFieldDayOfWeekShort => 'WT';

  @override
  String cronParserInvalidField(String field, String value) {
    return 'Ungueltiges Feld $field: \"$value\"';
  }

  @override
  String get cronsViewDescription =>
      'Geplante Aufgaben konfigurieren und verwalten. Unterstuetzt Cron-Ausdruecke, Timeouts, automatische Wiederholungen und Ausfuehrungshistorie.';

  @override
  String get cronsNewCronJob => 'Neuer Cron-Job';

  @override
  String get cronsEditCronJob => 'Cron-Job bearbeiten';

  @override
  String get cronsDeleteCronJobTitle => 'Cron-Job loeschen';

  @override
  String cronsDeleteCronJobMessage(String name) {
    return '\"$name\" loeschen? Dies kann nicht rueckgaengig gemacht werden. Die Ausfuehrungshistorie wird ebenfalls geloescht.';
  }

  @override
  String get cronsEmptyTitle => 'Noch keine Cron-Jobs konfiguriert';

  @override
  String get cronsEmptyBody =>
      'Klicken Sie oben auf \"Neuer Cron-Job\", um zu beginnen.';

  @override
  String get cronsCronExpressionTooltip => 'Cron-Ausdruck';

  @override
  String get cronsTimeoutTooltip => 'Timeout';

  @override
  String get cronsRetryCountTooltip => 'Wiederholungen';

  @override
  String get cronsMcpKeywordIndexLockedTooltip =>
      'Gesteuert durch Einstellungen -> MCP -> Aktualisierungsmodus des Keyword-Index';

  @override
  String get cronsRunOnceNow => 'Jetzt einmal ausfuehren';

  @override
  String get cronsHistory => 'Historie';

  @override
  String cronsLastRunAt(String time) {
    return 'Letzte: $time';
  }

  @override
  String get cronsFieldName => 'Name';

  @override
  String get cronsFieldNameHint => 'z. B. Taegliches Backup';

  @override
  String get cronsFieldDescription => 'Beschreibung';

  @override
  String get cronsFieldType => 'Typ';

  @override
  String get cronsFieldScriptFilePath => 'Skriptpfad';

  @override
  String get cronsFieldScriptFilePathHint =>
      'Eine .sh / .ps1 / .bat Datei waehlen';

  @override
  String get cronsBrowse => 'Durchsuchen';

  @override
  String get cronsFieldCommand => 'Befehl';

  @override
  String get cronsFieldCommandHintWindows =>
      'PowerShell- / BAT-Befehl eingeben';

  @override
  String get cronsFieldCommandHintShell => 'Shell-Befehl eingeben';

  @override
  String get cronsCronSchedule => 'Cron-Zeitplan';

  @override
  String get cronsCronScheduleHelper =>
      'Das Sekundenfeld bleibt 0. Kleinste Einheit: Minute. Format: Min Stunde Tag Monat Wochentag';

  @override
  String get cronsTimeoutSeconds => 'Timeout (s)';

  @override
  String get cronsRetries => 'Wiederholungen';

  @override
  String get cronsMaxRetryDelaySeconds => 'Max. Wiederholungsverzoegerung (s)';

  @override
  String get cronsRunAsUser => 'Ausfuehren als Benutzer';

  @override
  String get cronsDefaultCurrentUser => 'Standard (aktueller Benutzer)';

  @override
  String get cronsDefault => 'Standard';

  @override
  String get cronsTagsCommaSeparated => 'Tags (kommagetrennt)';

  @override
  String get cronsTagsHint => 'z. B. backup, cleanup';

  @override
  String get cronsWorkingDirectory => 'Arbeitsverzeichnis';

  @override
  String get cronsWorkingDirectoryHint =>
      'Optional, standardmaessig App-Verzeichnis';

  @override
  String get cronsEnvironmentVariables => 'Umgebungsvariablen';

  @override
  String get cronsEnvironmentVariablesHint =>
      'Eine pro Zeile, Format: KEY=VALUE';

  @override
  String get cronsExecutionContextCollection => 'Ausfuehrungskontext erfassen';

  @override
  String get cronsCollectAppMetadata => 'App-Metadaten erfassen';

  @override
  String get cronsCollectAppMetadataSubtitle =>
      'App-Version, PID, ausfuehrbaren Pfad usw. erfassen.';

  @override
  String get cronsCollectHostMetadata => 'Host-Metadaten erfassen';

  @override
  String get cronsCollectHostMetadataSubtitle =>
      'OS-Version, Hostname, CPU-Kerne usw. erfassen.';

  @override
  String get cronsCollectEnvironmentSnapshot => 'Umgebungs-Snapshot erfassen';

  @override
  String get cronsCollectEnvironmentSnapshotSubtitle =>
      'Effektive Laufzeit-Umgebungsvariablen erfassen (koennen sensible Daten enthalten).';

  @override
  String get cronsSensitive => 'Sensibel';

  @override
  String get cronsNotificationSettings => 'Benachrichtigungseinstellungen';

  @override
  String get cronsTestNotification => 'Benachrichtigung testen';

  @override
  String get cronsTestSuccessNotification => 'Erfolgsbenachrichtigung testen';

  @override
  String get cronsTestFailureNotification => 'Fehlerbenachrichtigung testen';

  @override
  String get cronsTestTimeoutNotification => 'Timeout-Benachrichtigung testen';

  @override
  String get cronsTestAllNotifications => 'Alle testen (nacheinander)';

  @override
  String get cronsNotificationSettingsHelper =>
      'Jedes Ereignis kann Kanal, Schweregrad, Ton und Vibration separat konfigurieren.';

  @override
  String get cronsOnSuccess => 'Bei Erfolg';

  @override
  String get cronsOnFailure => 'Bei Fehler';

  @override
  String get cronsOnTimeout => 'Bei Timeout';

  @override
  String get cronsEnabled => 'Aktiviert';

  @override
  String get cronsCustomNotificationMessageHint =>
      'Eigene Nachricht (optional)';

  @override
  String get cronsVibrationUnsupportedHint =>
      'Vibration wird auf dieser Plattform nicht unterstuetzt und ignoriert.';

  @override
  String get cronsValidationNameRequired => 'Cron-Job-Namen eingeben.';

  @override
  String get cronsValidationScriptRequired => 'Skriptdatei waehlen.';

  @override
  String get cronsValidationCommandRequired => 'Befehl eingeben.';

  @override
  String cronsValidationInvalidEnvironment(String lines) {
    return 'Ungueltiges Umgebungsvariablenformat in Zeile(n) $lines. KEY=VALUE verwenden.';
  }

  @override
  String get cronsNotificationSequentialStartTitle =>
      'Sequenzieller Test startet';

  @override
  String get cronsNotificationSequentialStartBody =>
      'Erfolgs-, Fehler- und Timeout-Benachrichtigungen werden nacheinander getestet.';

  @override
  String get cronsNotificationVibrationIgnoredTitle => 'Vibration ignoriert';

  @override
  String get cronsNotificationSequentialVibrationIgnoredBody =>
      'Vibration wird auf dieser Plattform nicht unterstuetzt und wurde im Sequenztest ignoriert.';

  @override
  String get cronsNotificationSequentialCompletedTitle =>
      'Sequenzieller Test abgeschlossen';

  @override
  String get cronsNotificationSequentialCompletedBody =>
      'Erfolgs-, Fehler- und Timeout-Benachrichtigungen wurden getestet.';

  @override
  String get cronsNotificationScenarioSuccess => 'Erfolg';

  @override
  String get cronsNotificationScenarioFailure => 'Fehler';

  @override
  String get cronsNotificationScenarioTimeout => 'Timeout';

  @override
  String get cronsNotificationScenarioAll => 'Alle';

  @override
  String cronsNotificationTestTitle(String label) {
    return 'Cron-Benachrichtigungstest - $label';
  }

  @override
  String get cronsNotificationTestDefaultBodySuccess =>
      'Testnachricht fuer Erfolg.';

  @override
  String get cronsNotificationTestDefaultBodyFailure =>
      'Testnachricht fuer Fehler.';

  @override
  String get cronsNotificationTestDefaultBodyTimeout =>
      'Testnachricht fuer Timeout.';

  @override
  String get cronsNotificationNoEmitBody =>
      'Aktuelle Einstellung ist Keine oder Nur Log; es wird keine Benachrichtigung gesendet.';

  @override
  String get cronsSystemNotificationUnavailableTitle =>
      'Systembenachrichtigung nicht verfuegbar';

  @override
  String get cronsSystemNotificationFallbackBody =>
      'Systembenachrichtigung fehlgeschlagen; Rueckfall auf In-App-Benachrichtigung.';

  @override
  String get cronsNotificationVibrationIgnoredBody =>
      'Vibration wird auf dieser Plattform nicht unterstuetzt und wurde ignoriert.';

  @override
  String get cronsUnknownPlatform => 'Unbekannte Plattform';

  @override
  String get cronsToggleOn => 'An';

  @override
  String get cronsToggleOff => 'Aus';

  @override
  String get cronsSupportBestEffortSystemSound =>
      'Unterstuetzt (Systemton nach Moeglichkeit)';

  @override
  String get cronsSupportSupported => 'Unterstuetzt';

  @override
  String get cronsSupportNotSupportedOnPlatform =>
      'Auf dieser Plattform nicht unterstuetzt';

  @override
  String get cronsSupportNotSupportedWillBeIgnored =>
      'Nicht unterstuetzt (wird ignoriert)';

  @override
  String get cronsSoundLabel => 'Ton';

  @override
  String get cronsVibrationLabel => 'Vibration';

  @override
  String get cronsPlatformLabel => 'Plattform';

  @override
  String get cronsSupportLabel => 'Support';

  @override
  String get cronsExecutionHistoryTitle =>
      'Ausfuehrungshistorie geplanter Aufgaben';

  @override
  String get cronsClearAllExecutionHistory =>
      'Gesamte Ausfuehrungshistorie loeschen';

  @override
  String get cronsNoExecutionRecords => 'Noch keine Ausfuehrungen';

  @override
  String get cronsClearExecutionHistoryTitle => 'Ausfuehrungshistorie loeschen';

  @override
  String cronsClearExecutionHistoryMessage(String name) {
    return 'Gesamte Ausfuehrungshistorie fuer \"$name\" loeschen? Dies kann nicht rueckgaengig gemacht werden.';
  }

  @override
  String get cronsClear => 'Leeren';

  @override
  String get cronsDeleteExecutionRecordTitle => 'Ausfuehrungseintrag loeschen';

  @override
  String get cronsDeleteExecutionRecordMessage =>
      'Diesen Ausfuehrungseintrag loeschen?';

  @override
  String get cronsExecutionStatusSuccess => 'Erfolg';

  @override
  String get cronsExecutionStatusFailed => 'Fehlgeschlagen';

  @override
  String get cronsExecutionStatusTimedOut => 'Timeout';

  @override
  String get cronsExecutionStatusRunning => 'Laeuft';

  @override
  String get cronsExecutionStatusKilled => 'Beendet';

  @override
  String get cronsTriggerManual => 'Manuell';

  @override
  String get cronsTriggerScheduled => 'Geplant';

  @override
  String get cronsDeleteThisRecord => 'Diesen Eintrag loeschen';

  @override
  String get cronsRetryAttempt => 'Wiederholungsversuch';

  @override
  String get cronsRunAs => 'Ausfuehren als';

  @override
  String get cronsWorkingDir => 'Arbeitsverz.';

  @override
  String get cronsScriptEnvironmentOverrides =>
      'Skript-Umgebungsueberschreibungen:';

  @override
  String get cronsEnvironmentSnapshot => 'Umgebungs-Snapshot:';

  @override
  String get cronsErrorReason => 'Fehler:';

  @override
  String get cronsStdout => 'stdout:';

  @override
  String get cronsStderr => 'stderr:';

  @override
  String get cronsExecutionContext => 'Ausfuehrungskontext:';

  @override
  String get cronsHermesTalkerReportTitle => 'Hermes Talker Bericht';

  @override
  String get cronsHermesNoEligibleSessions =>
      'In diesem Durchlauf wurden keine geeigneten Sitzungen gelernt.';

  @override
  String cronsHermesAffectedSessions(int count) {
    return 'Betroffene Sitzungen ($count)';
  }

  @override
  String cronsHermesStatsLine(
    int scanned,
    int triggered,
    int skipped,
    int errors,
  ) {
    return 'gescannt $scanned · ausgeloest $triggered · uebersprungen $skipped · Fehler $errors';
  }

  @override
  String get cronsHermesUntitledSession => '(unbenannte Sitzung)';

  @override
  String cronsHermesMemoryUpdates(int count) {
    return 'Speicher +$count';
  }

  @override
  String cronsHermesMemoryErrors(int count) {
    return 'Speicherfehler $count';
  }

  @override
  String cronsHermesSkillUpdates(int count) {
    return 'Skill +$count';
  }

  @override
  String cronsHermesSkillErrors(int count) {
    return 'Skill-Fehler $count';
  }

  @override
  String cronsHermesProfileChanges(int count) {
    return 'Profil $count';
  }

  @override
  String cronsHermesToolRounds(int count) {
    return 'Runden $count';
  }

  @override
  String get cronsHermesModelLabel => 'Modell';

  @override
  String get cronsHermesProviderLabel => 'Anbieter';

  @override
  String get cronsHermesTerminatedLabel => 'beendet';

  @override
  String get cronsHermesUserProfileChanges => 'Benutzerprofil-Aenderungen';

  @override
  String get cronsHermesMemoryChanges => 'Speicheraenderungen';

  @override
  String get cronsHermesSkillChanges => 'Skill-Aenderungen';

  @override
  String get cronsHermesAiReasoningOnScene => 'KI-Reasoning vor Ort';

  @override
  String get cronsHermesAiResponseOnScene => 'KI-Antwort vor Ort';

  @override
  String get cronsHermesNoFurtherDetails => 'Keine weiteren Details.';

  @override
  String get cronsHermesStatusError => 'Fehler';

  @override
  String get cronsHermesStatusSkipped => 'uebersprungen';

  @override
  String get cronsHermesStatusOk => 'ok';

  @override
  String get cronsHermesChangeBefore => 'vorher';

  @override
  String get cronsHermesChangeAfter => 'nachher';

  @override
  String get cronsHermesChangeValue => 'Wert';

  @override
  String get cronsHermesChangeSource => 'Quelle';

  @override
  String get cronsHermesChangeReason => 'Grund';

  @override
  String get cronsHermesChangeMetadata => 'Metadaten';

  @override
  String get cronsHermesChangeError => 'Fehler';

  @override
  String get cronsCollapse => 'Einklappen';

  @override
  String get cronsExpand => 'Ausklappen';

  @override
  String get aiModelAdd => 'Anbieter hinzufügen';

  @override
  String get aiModelsEmptyTitle => 'Noch keine Modellanbieter';

  @override
  String get aiModelsEmptyBody =>
      'Fügen Sie hier mindestens eine Modellanbieter-Konfiguration hinzu, dann verwendet der Thread-Editor sie direkt wieder.';

  @override
  String get aiModelDialogCreateTitle => 'Modellanbieter hinzufügen';

  @override
  String get aiModelDialogEditTitle => 'Modellanbieter bearbeiten';

  @override
  String get aiModelBaseUrl => 'Basis-URL';

  @override
  String get aiModelBaseUrlRequired => 'Basis-URL eingeben.';

  @override
  String get aiModelBaseUrlInvalid => 'Gültige Basis-URL eingeben.';

  @override
  String get aiModelOfficialWebsiteUrl => 'Website-URL (optional)';

  @override
  String get aiModelOfficialWebsiteUrlHint => 'https://example.com';

  @override
  String get aiModelOfficialWebsiteUrlInvalid =>
      'Gültige Website-URL eingeben.';

  @override
  String get aiModelOpenWebsiteFailure =>
      'Website konnte nicht geöffnet werden.';

  @override
  String get aiModelOpenWebsiteTooltip => 'Website öffnen';

  @override
  String get aiModelAuthScheme => 'Authentifizierungsschema';

  @override
  String get aiModelToken => 'Token';

  @override
  String get aiModelProtocol => 'Protokoll';

  @override
  String get aiModelSaveSuccess => 'Modellanbieter-Konfiguration gespeichert.';

  @override
  String get aiModelDeleteConfirmTitle => 'Modellanbieter löschen';

  @override
  String get aiModelDeleteConfirmBody =>
      'Diese Modellanbieter-Konfiguration löschen?';

  @override
  String get aiModelDeleteSuccess => 'Modellanbieter-Konfiguration gelöscht.';

  @override
  String get aiModelMoveUp => 'Nach oben';

  @override
  String get aiModelMoveDown => 'Nach unten';

  @override
  String get aiModelSelected => 'Aktiver Modellanbieter';

  @override
  String get aiModelNoToken => 'Kein Token konfiguriert';

  @override
  String get aiModelTest => 'Testen';

  @override
  String get aiModelTesting => 'Teste';

  @override
  String aiModelTestSuccess(String modelName) {
    return '$modelName hat den Test bestanden.';
  }

  @override
  String aiModelTestFailure(String modelName, String reason) {
    return '$modelName-Test fehlgeschlagen: $reason';
  }

  @override
  String get aiModelSelectionRequired =>
      'Fügen Sie zuerst in den Einstellungen einen KI-Modellanbieter hinzu und wählen Sie ihn aus.';

  @override
  String get aiModelScanButton => 'Modelle scannen';

  @override
  String get aiModelScanning => 'Verfügbare Modelle werden gescannt …';

  @override
  String get aiModelAvailableModels => 'Verfügbare Modelle';

  @override
  String get aiModelManualIdHint => 'Modell-ID manuell hinzufügen';

  @override
  String get aiModelManualIdAdd => 'Hinzufügen';

  @override
  String aiModelCount(int count) {
    return '$count Modelle';
  }

  @override
  String get chatModelButton => 'Modell auswählen';

  @override
  String get aiAuthNone => 'Keine';

  @override
  String get aiAuthBearer => 'Bearer';

  @override
  String get aiAuthToken => 'Token';

  @override
  String get aiAuthApiKey => 'API-Schlüssel';

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
  String get skillsPageTitle => 'Fähigkeiten';

  @override
  String get skillsPageSubtitle =>
      'Gib OpenHand mehr Erweiterbarkeit mit einer einheitlichen Ansicht installierter lokaler Skills und Vorlagen.';

  @override
  String get skillsSearchHint => 'Skills suchen';

  @override
  String get skillsRefresh => 'Aktualisieren';

  @override
  String get skillsOpenDirectory => 'Ordner öffnen';

  @override
  String get skillsImport => 'Skill importieren';

  @override
  String get skillsNewSkill => 'Neuer Skill';

  @override
  String get skillsEmptyTitle => 'Noch keine Skills installiert';

  @override
  String get skillsEmptyBody =>
      'Im aktuellen Skill-Verzeichnis wurden keine SKILL.md-Dateien gefunden. Erstelle eine Vorlage oder wechsle zu einem vorhandenen Verzeichnis.';

  @override
  String get skillsNoResultsTitle => 'Keine passenden Skills gefunden';

  @override
  String get skillsNoResultsBody =>
      'Versuche einen anderen Suchbegriff oder leere die Suche, um alle Skills erneut anzuzeigen.';

  @override
  String get skillTemplateCreated => 'Neue Skill-Vorlage erstellt';

  @override
  String get skillOperationFailed =>
      'Die Skill-Aktion ist fehlgeschlagen. Bitte versuche es erneut.';

  @override
  String get skillsImportSuccess => 'Skill importiert';

  @override
  String get skillsEdit => 'Skill bearbeiten';

  @override
  String get skillsDelete => 'Skill löschen';

  @override
  String get skillsPreviewClose => 'Schließen';

  @override
  String get skillsEditorLabel => 'SKILL.md-Inhalt';

  @override
  String get skillsCreateDialogTitle => 'Skill erstellen';

  @override
  String get skillsCreateNameLabel => 'Skill-Name';

  @override
  String get skillsCreateNameRequired => 'Skill-Namen eingeben.';

  @override
  String get skillsCreateIconLabel => 'Skill-Symbol';

  @override
  String get skillsCreateIconHint => 'Emoji oder lokales Bild auswählen.';

  @override
  String get skillsCreateIconRequired => 'Symbol auswählen.';

  @override
  String get skillsCreateIconChoose => 'Emoji wählen';

  @override
  String get skillsCreateIconChange => 'Ändern';

  @override
  String get skillsCreateImageChoose => 'Bild wählen';

  @override
  String get skillsCreateImageChange => 'Bild ersetzen';

  @override
  String get skillsCreateImageSelected => 'Lokales Bild ausgewählt';

  @override
  String get skillsCreateDescriptionLabel => 'Kurze Beschreibung';

  @override
  String get skillsCreateDescriptionRequired => 'Kurze Beschreibung eingeben.';

  @override
  String get skillsCreateContentRequired => 'SKILL.md-Inhalt eingeben.';

  @override
  String get imageEditorTitle => 'Bild bearbeiten';

  @override
  String get imageEditorCropHint =>
      'Ziehen Sie das Bild, um den quadratischen Beschnittbereich zu positionieren, dann passen Sie Zoom, Drehung, Helligkeit und Kontrast an.';

  @override
  String get imageEditorZoomLabel => 'Zoom';

  @override
  String get imageEditorBrightnessLabel => 'Helligkeit';

  @override
  String get imageEditorContrastLabel => 'Kontrast';

  @override
  String get imageEditorRotateLeft => 'Nach links drehen';

  @override
  String get imageEditorRotateRight => 'Nach rechts drehen';

  @override
  String get imageEditorReset => 'Zurücksetzen';

  @override
  String get imageEditorLoadFailed =>
      'Das ausgewählte Bild konnte nicht geladen werden.';

  @override
  String get imageEditorProcessFailed =>
      'Das ausgewählte Bild konnte nicht verarbeitet werden.';

  @override
  String get imageEditorSectionColor =>
      'Farbe (Farbtemperatur / Farbton / Gamma)';

  @override
  String get imageEditorSectionSplitToning => 'Split Toning (HSL)';

  @override
  String get imageEditorSectionDetail =>
      'Details (Klarheit / Schärfe / Rauschunterdrückung / Körnung)';

  @override
  String get imageEditorSectionEffects =>
      'Effekte (Dispersion / Verzerrung / Vignette)';

  @override
  String get imageEditorSectionWatermark => 'Textwasserzeichen / Markierung';

  @override
  String get imageEditorTemperatureLabel => 'Farbtemperatur';

  @override
  String get imageEditorTintLabel => 'Farbtonverschiebung';

  @override
  String get imageEditorGammaLabel => 'Gamma (Kurve)';

  @override
  String get imageEditorShadowHueLabel => 'Schatten-Farbton';

  @override
  String get imageEditorShadowStrengthLabel => 'Schatten-Intensität';

  @override
  String get imageEditorHighlightHueLabel => 'Lichter-Farbton';

  @override
  String get imageEditorHighlightStrengthLabel => 'Lichter-Intensität';

  @override
  String get imageEditorClarityLabel => 'Klarheit';

  @override
  String get imageEditorSharpnessLabel => 'Schärfe';

  @override
  String get imageEditorDenoiseLabel => 'Rauschunterdrückung';

  @override
  String get imageEditorGrainLabel => 'Körnung';

  @override
  String get imageEditorDispersionLabel => 'Streuung';

  @override
  String get imageEditorDistortLabel =>
      'Verzerrung (positiv wölbt / negativ streckt)';

  @override
  String get imageEditorWatermarkTextLabel => 'Wasserzeichentext';

  @override
  String get imageEditorWatermarkTextHint =>
      'Text zum Überlagern eingeben (leer lassen, um zu überspringen)';

  @override
  String get imageEditorWatermarkSizeLabel => 'Textgröße';

  @override
  String get imageEditorWatermarkOpacityLabel => 'Deckkraft';

  @override
  String get imageEditorWatermarkPositionLabel => 'Position';

  @override
  String get imageEditorAdvancedApplyHint =>
      'Anpassungen in den erweiterten Bereichen werden beim Speichern auf das Originalbild angewendet.';

  @override
  String get skillsEditorSave => 'Speichern';

  @override
  String get skillsEditorCancel => 'Abbrechen';

  @override
  String get skillsEditSuccess => 'Skill-Inhalt gespeichert';

  @override
  String get skillsDeleteConfirmTitle => 'Skill löschen';

  @override
  String get skillsDeleteConfirmBody =>
      'Beim Löschen werden das Skill-Verzeichnis und dessen SKILL.md-Inhalt dauerhaft entfernt.';

  @override
  String get skillsDeleteConfirmAction => 'Löschen';

  @override
  String get skillsDeleteSuccess => 'Skill gelöscht';

  @override
  String get skillsStorageSectionBody =>
      'Konfiguriere das lokale Verzeichnis, das OpenHand nach Skills durchsucht. Standardmäßig wird ~/.openhand/skills verwendet und bei Bedarf erstellt.';

  @override
  String get skillsStorageDefaultPath => 'Standardpfad';

  @override
  String get skillsStorageCurrentPath => 'Aktueller Pfad';

  @override
  String get skillsStorageSave => 'Speicherort speichern';

  @override
  String get skillsStorageBrowse => 'Ordner wählen';

  @override
  String get skillsStorageReset => 'Standard wiederherstellen';

  @override
  String get skillsStorageOpen => 'Speicherort öffnen';

  @override
  String get skillsStorageStatusError =>
      'Skill-Verzeichnis konnte nicht gelesen werden';

  @override
  String get skillsPathSaved => 'Der Skill-Speicherort wurde aktualisiert';

  @override
  String get instructionPageTitle => 'Anweisungen';

  @override
  String get instructionPageSubtitle =>
      'Verwalte wiederverwendbare Prompt-Bausteine. Aktivierte Anweisungen werden in aktueller Reihenfolge in jeden System-Prompt eingefügt und oberhalb des Composers als Chips angezeigt, die sich für einen einzelnen Versand umschalten lassen.';

  @override
  String get instructionRefresh => 'Aktualisieren';

  @override
  String get instructionNewEntry => 'Neue Anweisung';

  @override
  String get instructionEmptyTitle => 'Noch keine Anweisungen';

  @override
  String get instructionEmptyBody =>
      'Erstelle die erste wiederverwendbare Anweisung. OpenHand speichert sie im lokalen Anweisungsspeicher.';

  @override
  String get instructionLoadFailedTitle =>
      'Anweisungsspeicher konnte nicht geladen werden';

  @override
  String get instructionDeleteConfirmTitle => 'Anweisung löschen';

  @override
  String get instructionDeleteConfirmBody =>
      'Diese Anweisung löschen? Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get instructionEnabledStatus => 'Aktiviert und eingefügt';

  @override
  String get instructionDisabledStatus => 'Deaktiviert';

  @override
  String get instructionApplyToChipLabel => 'Gilt für';

  @override
  String get instructionNotesChipLabel => 'Notizen';

  @override
  String get instructionDialogCreateTitle => 'Neue Anweisung';

  @override
  String get instructionDialogEditTitle => 'Anweisung bearbeiten';

  @override
  String get instructionEnabledLabel => 'Aktiviert';

  @override
  String get instructionEnabledBody =>
      'Diese Anweisung in die aktive Prompt-Kette einfügen.';

  @override
  String get instructionNameField => 'Name *';

  @override
  String get instructionNameRequired => 'Gib einen Namen ein.';

  @override
  String get instructionDescriptionField => 'Beschreibung';

  @override
  String get instructionVersionField => 'Version';

  @override
  String get instructionApplyToField =>
      'Gilt für (beschreibe, wann diese Anweisung geladen wird)';

  @override
  String get instructionTaskTypesField =>
      'Auslösende Aufgabentypen (durch Kommas getrennt)';

  @override
  String get instructionKeywordsField =>
      'Auslösende Schlüsselwörter (durch Kommas getrennt)';

  @override
  String get instructionNotesField => 'Notizen (eine pro Zeile)';

  @override
  String get instructionBodyField => 'Anweisungstext * (Markdown)';

  @override
  String get instructionBodyRequired => 'Gib den Anweisungstext ein.';

  @override
  String get instructionCreateAction => 'Erstellen';

  @override
  String get instructionSaveFailed =>
      'Speichern fehlgeschlagen. Prüfe, ob Pflichtfelder leer sind.';

  @override
  String get memoryPageTitle => 'Speicher';

  @override
  String get memoryPageSubtitle =>
      'Verwalten Sie Nutzer-Erinnerungen in der lokalen Datenbank.';

  @override
  String get memoryRefresh => 'Aktualisieren';

  @override
  String get memoryNewEntry => 'Neue Erinnerung';

  @override
  String get memoryEmptyTitle => 'Noch keine Nutzer-Erinnerungen';

  @override
  String get memoryEmptyBody =>
      'Fügen Sie eine Nutzer-Erinnerung hinzu; OpenHand speichert sie lokal.';

  @override
  String get memoryLoadFailedTitle =>
      'Erinnerungsdaten konnten nicht geladen werden';

  @override
  String get memoryLoadFailedBody =>
      'Die Speicherdaten sind ungültig oder nicht verfügbar. Reparieren oder löschen Sie den Speicher und versuchen Sie es erneut.';

  @override
  String get memoryQuotaRecoveryTitle =>
      'Der Speicher überschreitet das Kontingent';

  @override
  String get memoryQuotaRecoveryBody =>
      'Es wird nur ein begrenzter Ausschnitt angezeigt. Löschen oder verkleinern Sie Einträge; neue Einträge sind vorübergehend deaktiviert.';

  @override
  String get memoryOperationFailed =>
      'Speicheraktion fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get memoryDialogCreateTitle => 'Nutzer-Erinnerung hinzufügen';

  @override
  String get memoryDialogEditTitle => 'Nutzer-Erinnerung bearbeiten';

  @override
  String get memoryContentField => 'Erinnerungsinhalt';

  @override
  String get memoryContentRequired => 'Erinnerungsinhalt eingeben.';

  @override
  String get memoryTagsField => 'Tags';

  @override
  String get memoryTagsHint => 'Tag eingeben und mit Enter hinzufügen';

  @override
  String get memoryTagLimitExceeded =>
      'Eine Erinnerung kann höchstens 32 Tags haben.';

  @override
  String get memoryDeleteConfirmTitle => 'Nutzer-Erinnerung löschen';

  @override
  String get memoryDeleteConfirmBody =>
      'Diese Nutzer-Erinnerung löschen? Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get memoryTypeUser => 'Vom Nutzer bearbeitet';

  @override
  String get memoryEntryCreated => 'Nutzer-Erinnerung erstellt.';

  @override
  String get memoryEntryUpdated => 'Nutzer-Erinnerung aktualisiert.';

  @override
  String get memoryEntryDeleted => 'Nutzer-Erinnerung gelöscht.';

  @override
  String get memoryEnabledLabel => 'Speicher aktivieren';

  @override
  String get memoryEnabledBody =>
      'Wenn deaktiviert, bleiben gespeicherte Nutzer-Erinnerungen auf der Festplatte, werden zur Laufzeit jedoch nicht verwendet.';

  @override
  String get userMemoryFileLabel => 'Erinnerungsdatenbank';

  @override
  String get memoryFileBody =>
      'Nutzer-Erinnerungen werden in OpenHands lokaler SQLite-Datenbank gespeichert.';

  @override
  String get memoryFileDefaultPath => 'Datenbankspeicherort';

  @override
  String get memoryOpenDirectory => 'Datenbankordner öffnen';

  @override
  String get memoryDisabledTitle => 'Speicher ist derzeit deaktiviert';

  @override
  String get memoryDisabledBody =>
      'Sie können Nutzer-Erinnerungen hier weiterhin verwalten. Um sie zur Laufzeit zu nutzen, aktivieren Sie den Speicher unter Einstellungen > Speicher.';

  @override
  String get memoryCreatedAtLabel => 'Erstellt am';

  @override
  String get memoryPersistenceSaveFailedTitle =>
      'Speichern der Erinnerung fehlgeschlagen';

  @override
  String get memoryPersistenceSaveFailedBody =>
      'Das Schreiben in die Erinnerungsdatenbank ist fehlgeschlagen. Nicht bestätigte Änderungen wurden nicht angewendet. Datenbankzugriff und Festplatte prüfen.';

  @override
  String get mcpPageTitle => 'MCP';

  @override
  String get mcpPageSubtitle =>
      'Lokale MCP-Server-Konfigurationen verwalten – im Cursor-Stil, an OpenHand angepasst.';

  @override
  String get mcpRefresh => 'Aktualisieren';

  @override
  String get mcpNewServer => 'Neuer Server';

  @override
  String get mcpEmptyTitle => 'Noch keine MCP-Dienste konfiguriert';

  @override
  String get mcpEmptyBody =>
      'Fügen Sie zuerst einen MCP-Server hinzu. OpenHand speichert ihn in ~/.openhand/mcp/mcp_servers.json.';

  @override
  String get mcpLoadFailedTitle => 'Laden der MCP-Konfiguration fehlgeschlagen';

  @override
  String get mcpOperationFailed =>
      'MCP-Aktion fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get mcpDialogCreateTitle => 'MCP-Dienst hinzufügen';

  @override
  String get mcpDialogEditTitle => 'MCP-Dienst bearbeiten';

  @override
  String get mcpNameField => 'Dienstname';

  @override
  String get mcpNameRequired => 'Dienstnamen eingeben.';

  @override
  String get mcpNameDuplicate => 'Dieser Dienstname existiert bereits.';

  @override
  String get mcpTypeField => 'Diensttyp';

  @override
  String get mcpUrlField => 'Dienst-URL';

  @override
  String get mcpUrlRequired => 'Dienst-URL eingeben.';

  @override
  String get mcpUrlInvalid => 'Gültige Dienst-URL eingeben.';

  @override
  String get mcpCommandField => 'Startbefehl';

  @override
  String get mcpCommandRequired => 'Startbefehl eingeben.';

  @override
  String get mcpArgsField => 'Befehlsargumente';

  @override
  String get mcpArgsHint => 'Ein Argument pro Zeile';

  @override
  String get mcpServerEnabledLabel => 'Diesen Dienst aktivieren';

  @override
  String get mcpServerEnabledBody =>
      'Wenn deaktiviert, bleibt die Dienstkonfiguration erhalten, der Server wird zur Laufzeit jedoch nicht aktiviert.';

  @override
  String get mcpServerStatusEnabled => 'Aktiviert';

  @override
  String get mcpServerStatusDisabled => 'Deaktiviert';

  @override
  String get mcpServerCreated => 'MCP-Dienst erstellt.';

  @override
  String get mcpServerUpdated => 'MCP-Dienst aktualisiert.';

  @override
  String get mcpServerDeleted => 'MCP-Dienst gelöscht.';

  @override
  String get mcpDeleteConfirmTitle => 'MCP-Dienst löschen';

  @override
  String get mcpDeleteConfirmBody => 'Diese MCP-Dienstkonfiguration löschen?';

  @override
  String mcpDeleteAlsoUninstallPackage(String packageName) {
    return 'Paket ebenfalls deinstallieren ($packageName)';
  }

  @override
  String get mcpDeleteAlsoUninstallPackageBody =>
      'Deinstalliert das globale Paket und bereinigt den isolierten Cache.';

  @override
  String mcpDependencyCleanedUp(String packageName) {
    return '$packageName-Abhängigkeit bereinigt';
  }

  @override
  String mcpDependencyCleanupFailed(String packageName, String error) {
    return '$packageName-Bereinigung fehlgeschlagen: $error';
  }

  @override
  String mcpDependencyCleanupError(String packageName, String error) {
    return '$packageName-Bereinigungsfehler: $error';
  }

  @override
  String get mcpTemplateSessionManaged => 'sitzungsverwaltet';

  @override
  String mcpTemplateSessionOn(String status) {
    return 'Sitzung an · $status';
  }

  @override
  String mcpTemplateSessionOff(String status) {
    return 'Sitzung aus · $status';
  }

  @override
  String get mcpTemplateNotRegistered => 'nicht registriert';

  @override
  String mcpTemplateRuntimeEnabledCount(int count) {
    return '$count Sitzungen an';
  }

  @override
  String get mcpDisabledTitle => 'MCP-Dienste sind derzeit deaktiviert';

  @override
  String get mcpDisabledBody =>
      'Sie können hier weiterhin Dienstkonfigurationen verwalten. Um sie zur Laufzeit zu aktivieren, schalten Sie den MCP-Schalter unter Einstellungen > MCP ein.';

  @override
  String get mcpTransportStreamableHttp => 'Streamable HTTP';

  @override
  String get mcpTransportSse => 'SSE';

  @override
  String get mcpTransportStdio => 'STDIO';

  @override
  String get mcpPersistenceSaveFailedTitle =>
      'Speichern der MCP-Konfiguration fehlgeschlagen';

  @override
  String get mcpPersistenceSaveFailedBody =>
      'Das Schreiben der MCP-Konfigurationsdatei ist fehlgeschlagen. Die Oberfläche wurde auf die letzte gültige Konfiguration zurückgesetzt. Dateiberechtigungen oder Festplattenzustand prüfen.';

  @override
  String get threadsEmptyBody =>
      'Noch keine Konversationsfäden. Erstellen Sie einen neuen Faden, um zu beginnen.';

  @override
  String get threadTemplateDialogTitle => 'Faden-Vorlage auswählen';

  @override
  String get threadTemplateDialogBody =>
      'Wählen Sie eine der unten stehenden integrierten Funktionsvorlagen, um einen neuen Faden zu starten.';

  @override
  String get threadCompressionNotice =>
      'Ältere Nachrichten in diesem Faden wurden in einen Zusammenfassungs-Checkpoint komprimiert, um den aktiven Prompt fokussiert zu halten.';

  @override
  String get threadCompressionCheckpointLabel => 'Zusammenfassungs-Checkpoint';

  @override
  String get aiCompressionThresholdLabel =>
      'Schwellwert für Nachrichtenkompression';

  @override
  String get aiCompressionThresholdBody =>
      'Wenn die unkomprimierten Verlaufsnachrichten im aktuellen Faden diesen Zeichen-Schwellwert überschreiten, fasst OpenHand den älteren Abschnitt zu einem Kompressions-Checkpoint zusammen und hält den neuesten Abschnitt aktiv.';

  @override
  String get aiCompressionThresholdSave => 'Schwellwert speichern';

  @override
  String get aiCompressionThresholdSaved =>
      'Schwellwert für KI-Nachrichtenkompression aktualisiert.';

  @override
  String get aiCompressionThresholdInvalid =>
      'Gültigen positiven ganzzahligen Schwellwert eingeben.';

  @override
  String get aiToolResultCompressionThresholdLabel =>
      'Schwellwert für Werkzeugaufruf-Ausgabekompression';

  @override
  String get aiToolResultCompressionThresholdSave => 'Schwellwert speichern';

  @override
  String get aiToolResultCompressionThresholdSaved =>
      'Schwellwert für Werkzeugaufruf-Ausgabekompression aktualisiert.';

  @override
  String get aiToolResultCompressionThresholdInvalid =>
      'Gültigen positiven ganzzahligen Schwellwert eingeben.';

  @override
  String get aiToolResultCompressionEnabledLabel =>
      'Werkzeugaufruf-Ausgabekompression aktivieren';

  @override
  String get aiToolResultCompressionEnabledBody =>
      'Steuert, ob lange Werkzeugausgaben beim Erstellen von Kompressions-Checkpoints zusammengefasst werden. Normale Gespräche liefern dem Modell immer vollständige Ergebnisse; bei Deaktivierung bleiben auch in Checkpoints Rohausgaben erhalten, was die Kompressionskosten erhöhen kann.';

  @override
  String get aiMicroCompressionEnabledLabel => 'Mikro-Kompression';

  @override
  String get aiMicroCompressionEnabledBody =>
      'Wenn aktiviert, werden ältere konsumierte Werkzeugergebnisse nur in Kompressions-Checkpoint-Prompts kompaktiert. Das senkt Zusammenfassungskosten und hält den aktiven Verlauf cache-stabil. Wenn deaktiviert, folgen lange alte Ergebnisse weiter der Schwellenwert-Zusammenfassung oben.';

  @override
  String get aiMessageContentSectionLabel => 'Nachrichteninhalt';

  @override
  String get aiMessageContentFormatLabel => 'Inhaltsformat';

  @override
  String get aiMessageContentFormatBody =>
      'Steuert, wie KI-Assistentennachrichten dargestellt werden. Markdown ist die Vorgabe; Klartext ist am schnellsten; HTML wird per Drittanbieter-Bibliothek gerendert (höhere Tokenkosten) und fällt bei Renderfehlern gemäß der Regel unten zurück.';

  @override
  String get aiMessageContentFormatMarkdown => 'Markdown';

  @override
  String get aiMessageContentFormatPlainText => 'Klartext';

  @override
  String get aiMessageContentFormatHtml => 'HTML';

  @override
  String get aiMessageContentFormatHtmlTokenWarning =>
      'Der HTML-Modus injiziert zusätzliche Formatvorgaben in jeden Prompt; die Tokenkosten sind etwas höher.';

  @override
  String get aiHtmlRenderFallbackLabel => 'HTML-Render-Fallback';

  @override
  String get aiHtmlRenderFallbackBody =>
      'Strategie bei HTML-Parser- oder Renderfehlern. Markdown analysiert erneut als Markdown; Klartext zeigt den Rohtext direkt.';

  @override
  String get aiHtmlRenderFallbackMarkdown => 'Markdown';

  @override
  String get aiHtmlRenderFallbackPlainText => 'Klartext';

  @override
  String get aiHtmlContentRichnessLabel => 'HTML-Inhaltsfülle';

  @override
  String get aiHtmlContentRichnessBody =>
      'Steuert die visuelle Intensität, die im HTML-Modus an das Modell weitergegeben wird. Ausgewogen ist Standard (zurückhaltend in Graustufen); Reich gibt Farben und Karten frei; Lebhaft treibt Verläufe, Glasmorphismus und Hero-Blöcke auf die Spitze – höchste Token-Kosten.';

  @override
  String get aiHtmlContentRichnessBalanced => 'Ausgewogen';

  @override
  String get aiHtmlContentRichnessRich => 'Reich';

  @override
  String get aiHtmlContentRichnessVivid => 'Lebhaft';

  @override
  String get aiToolResultCompressionHeadTailWindowLabel =>
      'Kompressions-Kopf-/Endfenster';

  @override
  String get aiToolResultCompressionHeadTailWindowBody =>
      'Wie viele Kopf-/Endzeichen der Rohausgabe in der verdichteten Zusammenfassung erhalten bleiben. Standard 256; 0 deaktiviert Kopf-/Endausschnitte; Bereich 0–8192.';

  @override
  String get aiToolResultCompressionHeadTailWindowSave => 'Fenster speichern';

  @override
  String get aiToolResultCompressionHeadTailWindowSaved =>
      'Kopf-/Endfenster aktualisiert.';

  @override
  String get aiToolResultCompressionHeadTailWindowInvalid =>
      'Ganzzahl zwischen 0 und 8192 eingeben.';

  @override
  String get aiToolResultCompressionMaxPathHitsLabel =>
      'Kompressions-Pfad-Extraktionslimit';

  @override
  String get aiToolResultCompressionMaxPathHitsBody =>
      'Maximale Anzahl betroffener Dateipfade, die in die Zusammenfassung extrahiert werden. Standard 12; 0 deaktiviert Extraktion; Bereich 0–200.';

  @override
  String get aiToolResultCompressionMaxPathHitsSave => 'Limit speichern';

  @override
  String get aiToolResultCompressionMaxPathHitsSaved =>
      'Pfad-Extraktionslimit aktualisiert.';

  @override
  String get aiToolResultCompressionMaxPathHitsInvalid =>
      'Ganzzahl zwischen 0 und 200 eingeben.';

  @override
  String get aiWriteToolSummaryMaxCharsLabel =>
      'Zeichenlimit der Write-Werkzeug-Zusammenfassung';

  @override
  String get aiWriteToolSummaryMaxCharsBody =>
      'Maximale Zeichen von result_text in Zusammenfassungen von Schreibwerkzeugen (write/edit/multiedit/notebookedit/write-ähnliche bash). Standard 280; 0 lässt die Zusammenfassung aus; Bereich 0–8192.';

  @override
  String get aiWriteToolSummaryMaxCharsSave => 'Limit speichern';

  @override
  String get aiWriteToolSummaryMaxCharsSaved =>
      'Zeichenlimit der Write-Werkzeug-Zusammenfassung aktualisiert.';

  @override
  String get aiWriteToolSummaryMaxCharsInvalid =>
      'Ganzzahl zwischen 0 und 8192 eingeben.';

  @override
  String get aiMaxRecentErrorsLabel => 'Aufbewahrung kürzlicher Sitzungsfehler';

  @override
  String get aiMaxRecentErrorsBody =>
      'Anzahl der kürzlichen Fehlerdatensätze, die im KI-Sitzungszustand gespeichert werden. Standard 20; Bereich 0–1000.';

  @override
  String get aiMaxRecentErrorsSave => 'Limit speichern';

  @override
  String get aiMaxRecentErrorsSaved =>
      'Aufbewahrung kürzlicher Sitzungsfehler aktualisiert.';

  @override
  String get aiMaxRecentErrorsInvalid =>
      'Ganzzahl zwischen 0 und 1000 eingeben.';

  @override
  String get aiMaxPlanHistoryEntriesLabel => 'Aufbewahrung des Planverlaufs';

  @override
  String get aiMaxPlanHistoryEntriesBody =>
      'Maximale Einträge im plan_history im Plan-Modus. Standard 20; Bereich 0–1000.';

  @override
  String get aiMaxPlanHistoryEntriesSave => 'Limit speichern';

  @override
  String get aiMaxPlanHistoryEntriesSaved =>
      'Aufbewahrung des Planverlaufs aktualisiert.';

  @override
  String get aiMaxPlanHistoryEntriesInvalid =>
      'Ganzzahl zwischen 0 und 1000 eingeben.';

  @override
  String get aiMaxTruncationContinuationsLabel => 'Auto-Fortsetzungslimit';

  @override
  String get aiMaxTruncationContinuationsBody =>
      'Maximale aufeinanderfolgende automatische Fortsetzungen, nachdem die Modellausgabe abgeschnitten wurde (finish_reason=length). Standard 5; Bereich 0–100.';

  @override
  String get aiMaxTruncationContinuationsSave => 'Limit speichern';

  @override
  String get aiMaxTruncationContinuationsSaved =>
      'Auto-Fortsetzungslimit aktualisiert.';

  @override
  String get aiMaxTruncationContinuationsInvalid =>
      'Ganzzahl zwischen 0 und 100 eingeben.';

  @override
  String get aiEstimatedCharactersPerTokenLabel =>
      'Geschätztes Verhältnis Zeichen pro Token';

  @override
  String get aiEstimatedCharactersPerTokenBody =>
      'Ungefähre Zeichen pro Token, verwendet für Kontextbudget-Schätzungen. Standard 4; Bereich 1–32.';

  @override
  String get aiEstimatedCharactersPerTokenSave => 'Verhältnis speichern';

  @override
  String get aiEstimatedCharactersPerTokenSaved =>
      'Geschätztes Verhältnis Zeichen pro Token aktualisiert.';

  @override
  String get aiEstimatedCharactersPerTokenInvalid =>
      'Ganzzahl zwischen 1 und 32 eingeben.';

  @override
  String get aiImageSizeLimitBody =>
      'Wenn der Nutzer ein Bild größer als dieses Limit anhängt, komprimiert OpenHand es automatisch (Qualität + Auflösung) vor dem Senden. Akzeptiert MB-Dezimalwerte; Bereich 0,0625 MB (64 KB) bis 64 MB.';

  @override
  String get aiImageSizeLimitFieldLabel => 'Limit (MB)';

  @override
  String get aiImageSizeLimitSave => 'Limit speichern';

  @override
  String get aiImageSizeLimitSaved => 'Bildanhang-Größenlimit aktualisiert.';

  @override
  String get aiImageSizeLimitInvalid => 'Gültige positive MB-Zahl eingeben.';

  @override
  String get imageEditorAspectFree => 'Frei';

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
  String get imageEditorAspectCircle => 'Kreis';

  @override
  String get imageEditorFlipHorizontal => 'Horizontal spiegeln';

  @override
  String get imageEditorFlipVertical => 'Vertikal spiegeln';

  @override
  String get imageEditorSaturationLabel => 'Sättigung';

  @override
  String get imageEditorExposureLabel => 'Belichtung';

  @override
  String get imageEditorHueLabel => 'Farbton';

  @override
  String get imageEditorVignetteLabel => 'Vignette';

  @override
  String get imageEditorFineRotationLabel => 'Feinrotation (°)';

  @override
  String get imageEditorSaveToFile => 'In Datei speichern';

  @override
  String get imageEditorCopyToClipboard => 'In Zwischenablage kopieren';

  @override
  String imageEditorSavedTo(String path) {
    return 'Gespeichert: $path';
  }

  @override
  String imageEditorSaveFailed(String error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String get imageEditorClipboardCopiedBitmap =>
      'Bild in die Zwischenablage kopiert. Der Dateipfad wurde ebenfalls als Text kopiert.';

  @override
  String imageEditorClipboardCopiedPath(String path) {
    return 'Bilddateipfad in die Zwischenablage kopiert: $path';
  }

  @override
  String get imageEditorApplyButton => 'Anwenden';

  @override
  String get imageEditorUndoButton => 'Rückgängig';

  @override
  String get imageEditorResetAllButton => 'Alles zurücksetzen';

  @override
  String get imageEditorCompareHold => 'Halten zum Vergleichen';

  @override
  String get imageEditorCompareRelease => 'Loslassen';

  @override
  String get imageEditorCompareOriginal => 'Original';

  @override
  String get imageEditorWatermarkColorLabel => 'Textfarbe';

  @override
  String get imageEditorWatermarkColorHue => 'Farbton';

  @override
  String get imageEditorWatermarkColorSaturation => 'Sättigung';

  @override
  String get imageEditorWatermarkColorLightness => 'Helligkeit';

  @override
  String get imageEditorApplySuccess => 'Anpassungen angewendet';

  @override
  String get imageEditorProcessing => 'Verarbeitung …';

  @override
  String get builtinToolTimeoutLabel => 'Timeout (Sekunden)';

  @override
  String builtinToolTimeoutHint(int seconds) {
    return 'Standard ${seconds}s';
  }

  @override
  String builtinToolTimeoutHelper(int seconds) {
    return 'Leer = Standard ${seconds}s. Laufzeit-Schutz nur für nebenwirkungsfreie Werkzeuge; Task/Bash/Schreibwerkzeuge nutzen eigene Grenzen.';
  }

  @override
  String get builtinToolRetryLabel =>
      'Bei Fehlschlag / Timeout erneut versuchen';

  @override
  String get builtinToolRetryBody =>
      'Standardmäßig aus. Wiederholt nur nebenwirkungsfreie Werkzeuge bei echten failed/timed_out-Ergebnissen; keine ungültigen Argumente, abgelehnten Aufrufe, Task-Aufrufe, Schreibbefehle, Dateiänderungen, Hintergrundprozesse, Skill-Änderungen oder Speicher-Schreibvorgänge.';

  @override
  String builtinToolMaxRetriesLabel(int max) {
    return 'Max. Wiederholungen (0–$max)';
  }

  @override
  String builtinToolMaxRetriesHelper(int max) {
    return 'Erstversuch ausgenommen; bei $max begrenzt';
  }

  @override
  String get builtinToolBackoffLabel => 'Wiederholungs-Backoff-Basis (ms)';

  @override
  String builtinToolBackoffHint(int ms) {
    return 'Standard ${ms}ms';
  }

  @override
  String builtinToolBackoffHelper(int max) {
    return 'Exponentiell: n-te Wiederholung wartet Basis × 2^(N-1) ms, begrenzt auf ${max}ms';
  }

  @override
  String selfLearningFlushIntervalLabel(int ms) {
    return 'Stream-Flush-Intervall: ${ms}ms';
  }

  @override
  String selfLearningFlushIntervalHelper(int min, int max) {
    return 'Persistenzintervall für die Streaming-Ausgabe der Selbstlernkarte ($min–${max}ms). Kleiner = mehr Echtzeit, aber mehr Layout-Jitter; größer = glatter, aber höhere Latenz pro Chunk. Standard 600ms.';
  }

  @override
  String get tsmRenameThreadTitle => 'Thread umbenennen';

  @override
  String get tsmRenameHint => 'Thread-Titel eingeben';

  @override
  String get tsmRenameFailed => 'Umbenennen fehlgeschlagen';

  @override
  String get tsmDeleteThreadTitle => 'Thread löschen';

  @override
  String get tsmDeleteSelectedTitle => 'Ausgewählte Threads löschen';

  @override
  String tsmDeleteSelectedConfirm(int count) {
    return '$count Thread(s) und ihre Nachrichten werden endgültig gelöscht. Dieser Vorgang kann nicht rückgängig gemacht werden.';
  }

  @override
  String tsmDeleteFailedCount(int count) {
    return '$count Thread(s) konnten nicht gelöscht werden';
  }

  @override
  String get tsmSessionMissing => 'Sitzung fehlt oder wurde gelöscht';

  @override
  String get tsmExportSessionDataTitle => 'Sitzungsdaten exportieren';

  @override
  String tsmExportingSession(String title) {
    return 'Exportiere „$title“…';
  }

  @override
  String get tsmExportComplete => 'Export abgeschlossen';

  @override
  String get tsmExportFailed => 'Export fehlgeschlagen';

  @override
  String get tsmChooseExportFolder => 'Exportordner auswählen';

  @override
  String get tsmBatchExportTitle => 'Stapelexport';

  @override
  String tsmBatchExportSubtitle(int count) {
    return '$count Threads werden gleich exportiert…';
  }

  @override
  String tsmBatchExportDone(int ok, int failed) {
    return 'Stapelexport abgeschlossen: $ok erfolgreich / $failed fehlgeschlagen';
  }

  @override
  String get tsmMenuPreview => 'Vorschau';

  @override
  String get tsmMenuRename => 'Umbenennen';

  @override
  String get tsmMenuExportSession => 'Sitzung exportieren';

  @override
  String get tsmMenuPin => 'Anheften';

  @override
  String get tsmMenuUnpin => 'Lösen';

  @override
  String get tsmMenuArchive => 'Archivieren';

  @override
  String get tsmMenuUnarchive => 'Aus Archiv holen';

  @override
  String get tsmMenuDelete => 'Löschen';

  @override
  String get tsmPinUpdateFailed =>
      'Anheft-Status konnte nicht aktualisiert werden';

  @override
  String get tsmArchiveUpdateFailed =>
      'Archivstatus konnte nicht aktualisiert werden';

  @override
  String get tsmUntitledThread => '(Unbenannter Thread)';

  @override
  String tsmPreviewMessageCount(int count) {
    return '$count Nachrichten';
  }

  @override
  String get tsmClosePreview => 'Vorschau schließen';

  @override
  String get tsmNoMessages => 'Keine Nachrichten';

  @override
  String get tsmEmptyMessage => '(leer)';

  @override
  String get tsmSearchHint => 'Nach Titel oder ID suchen';

  @override
  String get tsmDensityComfortable => 'Komfortabel';

  @override
  String get tsmDensityCompact => 'Kompakt';

  @override
  String get tsmAllTemplates => 'Alle Vorlagen';

  @override
  String tsmSortDisabledHint(String mode) {
    return 'Sortiert nach „$mode\". Ziehgriffe sind deaktiviert; wechseln Sie zurück zu „Manuelle Reihenfolge\", um neu anzuordnen.';
  }

  @override
  String get tsmSortManual => 'Manuelle Reihenfolge';

  @override
  String get tsmSortUpdated => 'Zuletzt aktualisiert';

  @override
  String get tsmSortCreated => 'Zuletzt erstellt';

  @override
  String get tsmSortSize => 'Nach Größe';

  @override
  String get tsmSortMessages => 'Nach Nachrichten';

  @override
  String get tsmSortToken => 'Nach Token';

  @override
  String get tsmHideArchived => 'Archivierte ausblenden';

  @override
  String get tsmShowArchived => 'Archivierte einblenden';

  @override
  String get tsmExitSelection => 'Auswahl beenden';

  @override
  String get tsmEnterSelection => 'Mehrfachauswahl';

  @override
  String get tsmClose => 'Schließen';

  @override
  String get tsmTitle => 'Thread-Sitzungsverwaltung';

  @override
  String tsmHeaderSubtitle(int count) {
    return '$count Thread(s) · Lange drücken oder Griff ziehen, um neu zu sortieren; Doppelklick / Rechtsklick für mehr';
  }

  @override
  String tsmSelectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get tsmBatchExportButton => 'Stapelexport';

  @override
  String get tsmDeleteSelectedButton => 'Auswahl löschen';

  @override
  String get tsmEmptyState => 'Noch keine Thread-Sitzungen';

  @override
  String get tsmCancel => 'Abbrechen';

  @override
  String get settingsThreadSessionManagementTitle =>
      'Thread-Sitzungsverwaltung';

  @override
  String get settingsThreadSessionManagementSubtitle =>
      'Übersicht über Titel, Erstell- und Aktualisierungszeit, Speicherbedarf, Nachrichtenzusammensetzung sowie Token-Statistik aller Threads. Unterstützt Drag-and-Drop-Sortierung, Mehrfachauswahl-Löschen sowie Doppelklick- bzw. Rechtsklick-Menüs zum Umbenennen, Exportieren und Löschen. Die Ein- und Ausblendanimation des Dialogs folgt der globalen Dialoganimationskonfiguration.';

  @override
  String get settingsThreadSessionManagementOpen => 'Verwaltung öffnen';

  @override
  String get settingsMessageGatewayTitle => 'Nachrichten-Gateway';

  @override
  String get settingsMessageGatewayDescription =>
      'Konfigurieren Sie die integrierte allgemeine Web-Nachrichtenplattform mit Listener, Authentifizierung, Sitzungen, Web-Chat, Integritätsprüfungen, Protokollen und Betrieb.';

  @override
  String get tsmRowUnknown => 'unbekannt';

  @override
  String get tsmRowCreated => 'Erstellt';

  @override
  String get tsmRowUpdated => 'Aktualisiert';

  @override
  String get tsmRowSize => 'Größe';

  @override
  String get tsmRowMessages => 'Nachrichten';

  @override
  String get tsmRowToken => 'Token';

  @override
  String get tsmRowByKind => 'Aufteilung';

  @override
  String get inputRepairTitle => 'Eingabe-Reparatur';

  @override
  String get inputRepairBody =>
      'Beseitigt verwaiste Kindprozesse (osascript, LSP, MCP, …) und setzt den macOS-Eingabe­methoden-Kontext zurück — behebt globale TextField-Probleme bei Eingabe, Kopieren/Einfügen oder ESC.';

  @override
  String get inputRepairButton => 'Eingabe reparieren';

  @override
  String get inputRepairDone => 'Eingabekontext zurückgesetzt.';

  @override
  String inputRepairDoneDetail(int count) {
    return 'Eingabekontext zurückgesetzt; $count Hintergrund-Kindprozesse beendet.';
  }

  @override
  String get proxySectionTitle => 'System';

  @override
  String get proxySectionBody =>
      'Alle internen HTTP-Clients (WebSearch / WebFetch usw.) verwenden den hier gewählten Proxy. Änderungen werden sofort übernommen, kein Neustart erforderlich.';

  @override
  String get proxyModeLabel => 'Proxy-Modus';

  @override
  String get proxyModeBody =>
      'Legt fest, wie die internen HTTP-Clients (WebSearch / WebFetch usw.) einen Proxy auswählen.';

  @override
  String get proxyModeDisabled => 'Kein Proxy';

  @override
  String get proxyModeAutomatic => 'Automatisch erkennen (Standard)';

  @override
  String get proxyModeManual => 'Manuell';

  @override
  String get proxyProtocolsLabel => 'Protokolle';

  @override
  String get proxyProtocolsBody =>
      'Mehrfachauswahl. Mindestens eines muss aktiv bleiben; bei Leerung wird HTTP + HTTPS wiederhergestellt.';

  @override
  String get proxyHostLabel => 'Server (IP oder Hostname)';

  @override
  String get proxyPortLabel => 'Port';

  @override
  String get proxyAuthLabel => 'Proxy-Authentifizierung aktivieren';

  @override
  String get proxyAuthBody =>
      'Benutzername / Passwort werden nur verwendet, wenn aktiviert (HTTP Basic).';

  @override
  String get proxyUsernameLabel => 'Benutzername';

  @override
  String get proxyPasswordLabel => 'Passwort';

  @override
  String get proxyExceptionsLabel =>
      'Proxy für diese Hosts und Domains umgehen';

  @override
  String get proxyExceptionsBody =>
      'Ein Eintrag pro Zeile. Unterstützt: IP (127.0.0.1), IPv4-CIDR (192.168.0.0/16), Domain (example.com inkl. Subdomains), Glob (*.example.com) und Regex (/^api\\d+\\.example\\.com\$/i). localhost / 127.0.0.1 / ::1 immer direkt.';

  @override
  String get proxyExceptionsHint =>
      'z. B.:\n*.local\n10.0.0.0/8\n/^api\\d+\\.example\\.com\$/i';

  @override
  String get proxyTestButton => 'Proxy-Verbindung testen';

  @override
  String get proxyTesting => 'Wird getestet…';

  @override
  String proxyTestSuccess(int latency, String via) {
    return 'OK ($latency ms, über $via)';
  }

  @override
  String proxyTestFailure(String reason) {
    return 'Fehlgeschlagen: $reason';
  }

  @override
  String get proxyTestEndpointLabel => 'Test-URL';

  @override
  String get proxyTestEndpointHint =>
      'Standard: https://www.google.com/generate_204';

  @override
  String get proxyTestVerdictDirect => 'direkt';

  @override
  String proxyTestVerdictProxy(String endpoint) {
    return 'Proxy $endpoint';
  }

  @override
  String get proxyTestEndpointInvalid =>
      'Test-URL ist ungültig (muss mit http:// oder https:// beginnen)';

  @override
  String get proxyTestConsoleTitle => 'Proxy-Verbindungsdiagnose';

  @override
  String get proxyTestConsoleRunning => 'Route wird geprüft…';

  @override
  String get proxyTestConsoleSucceeded => 'Fertig: Route in Ordnung';

  @override
  String get proxyTestConsoleFailed => 'Fertig: Probleme erkannt';

  @override
  String get proxyTestConsoleCopy => 'Protokoll kopieren';

  @override
  String get proxyTestConsoleCopied => 'Protokoll in Zwischenablage kopiert';

  @override
  String get proxyTestConsoleClose => 'Schließen';

  @override
  String get proxyTestConsoleRerun => 'Erneut ausführen';

  @override
  String get proxyTestConsoleMaximize => 'Maximieren';

  @override
  String get proxyTestConsoleRestore => 'Wiederherstellen';

  @override
  String get proxyTestConsoleClear => 'Konsole leeren';

  @override
  String get tokenPopupCostHeading => 'Kosten';

  @override
  String get tokenPopupCostInput => 'Eingabe';

  @override
  String get tokenPopupCostOutput => 'Ausgabe';

  @override
  String get tokenPopupCostCacheRead => 'Zwischenspeicher-Treffer';

  @override
  String get tokenPopupCostCacheWrite => 'Zwischenspeicher-Schreiben';

  @override
  String get tokenPopupCostTotal => 'Gesamt';

  @override
  String get tokenDialUnit => 'Token';

  @override
  String get tokenPopupInputHeading => 'Eingabe';

  @override
  String get tokenPopupPrompt => 'Eingabetext';

  @override
  String get tokenPopupAudioInput => 'Audioeingabe';

  @override
  String get tokenPopupImageInput => 'Bildeingabe';

  @override
  String get tokenPopupVideoInput => 'Videoeingabe';

  @override
  String get tokenPopupCacheRead => 'Zwischenspeicher-Treffer';

  @override
  String get tokenPopupCacheWrite => 'Zwischenspeicher-Schreiben';

  @override
  String get tokenPopupOutputHeading => 'Ausgabe';

  @override
  String get tokenPopupCompletion => 'Antwort';

  @override
  String get tokenPopupReasoning => 'Denkprozess';

  @override
  String get tokenPopupWebSearchHeading => 'Websuche';

  @override
  String get tokenPopupWebSearchCalls => 'Aufrufe';

  @override
  String get tokenPopupWebSearchPages => 'Seiten';

  @override
  String get tokenPopupGrandTotal => 'Gesamt';

  @override
  String get tokenPopupContextOverview => 'Kontextübersicht';

  @override
  String get tokenPopupContextMeasured =>
      'Gesamtsumme gemessen · Kategorien verteilt';

  @override
  String get tokenPopupContextEstimated => 'Aus Anfrageinhalt geschätzt';

  @override
  String get tokenPopupContextEmpty =>
      'Nächste Nachricht senden, um die Übersicht zu erstellen';

  @override
  String get tokenPopupContextSystemPrompt => 'System-Prompt';

  @override
  String get tokenPopupContextBuiltinTools => 'Integrierte Tools';

  @override
  String get tokenPopupContextMcp => 'MCP';

  @override
  String get tokenPopupContextInstructions => 'Anweisungen';

  @override
  String get tokenPopupContextMemory => 'Speicher';

  @override
  String get tokenPopupContextSkills => 'Skills';

  @override
  String get tokenPopupContextHooks => 'Hooks';

  @override
  String get tokenPopupContextConversation => 'Unterhaltung';

  @override
  String get tokenPopupContextRuntime => 'Laufzeit';

  @override
  String get tokenPopupContextWindow => 'Kontextfenster';

  @override
  String get tokenPopupCompactNow => 'Jetzt komprimieren';

  @override
  String get tokenPopupCompacting => 'Komprimierung…';

  @override
  String get tokenPopupSessionHeading => 'Sitzung';

  @override
  String get tokenPopupMessages => 'Nachrichten';

  @override
  String get tokenPopupPromptBuilds => 'Eingabeaufbauten';

  @override
  String get tokenPopupPromptChars => 'Eingabezeichen';

  @override
  String get tokenPopupCacheHitModeExcludeExpired => 'Ohne Ablauf-Ausreißer';

  @override
  String get tokenPopupCacheHitModeIncludeExpired => 'Mit Ablauf-Ausreißern';

  @override
  String tokenPopupExcludedRounds(int count) {
    return '$count ausgeschlossen';
  }

  @override
  String get tokenPopupPrefixReuse => 'Präfix-Wiederverwendung';

  @override
  String tokenPopupTooltipFreshReuse(String fresh, int reuse) {
    return '+$fresh neu · Wiederverw. $reuse%';
  }

  @override
  String get tokenPopupFirstRequestShort => 'Ignoriert';

  @override
  String get tokenPopupFirstRequestNotAveraged => 'Nicht im Schnitt';

  @override
  String get tokenPopupTrendNoData =>
      'Noch keine Daten zur Trefferquote. Der Trend erscheint nach gesendeten Nachrichten.';

  @override
  String get tokenPopupTrendOnlyFirstIgnored =>
      'Die erste Anfrage zählt nicht. Der Trend startet nach der nächsten normalen Anfrage.';

  @override
  String get tokenPopupTrendFirstReferenceOnly =>
      'Die erste Anfrage dient nur als Referenz und zählt nicht zum Durchschnitt.';

  @override
  String get tokenPopupUncached => 'Nicht gespeichert';

  @override
  String get toolbarSessionMetadata => 'Sitzungsmetadaten';

  @override
  String get toolbarShowPlan => 'Plan einblenden';

  @override
  String get toolbarHidePlan => 'Plan ausblenden';

  @override
  String get toolbarPlanAwaitingApproval => 'Plan wartet auf Freigabe';

  @override
  String get toolbarPlanNeedsReview => 'Plan zu prüfen';

  @override
  String get toolbarPlanNeedsAttention => 'Plan benötigt Aufmerksamkeit';

  @override
  String get toolbarPlanCompleted => 'Plan abgeschlossen';

  @override
  String get toolbarPlanInProgress => 'Plan in Bearbeitung';

  @override
  String get toolbarPlanConfirmToBegin => 'Zur Ausführung bestätigen';

  @override
  String get toolbarPlanInspectBeforeResume =>
      'Vor dem Fortsetzen abgeschlossene Schritte, Artefakte und Todos prüfen';

  @override
  String get toolbarPlanStepFailed =>
      'Ein Schritt schlug fehl. Bitte prüfen und fortfahren.';

  @override
  String get toolbarPlanPending => 'Ausstehend';

  @override
  String get toolbarPlanReview => 'Zur Prüfung';

  @override
  String get toolbarToolsProtocolUnsupported =>
      'Das aktuelle Modellprotokoll unterstützt keine Tool-Aufrufe';

  @override
  String get toolbarRuntimeNoSnapshot => 'Noch kein Laufzeit-Tool-Snapshot';

  @override
  String get toolbarToolsCatalogStale =>
      'Tool-Katalog veraltet, wird nächste Runde aktualisiert';

  @override
  String get toolbarRuntimeCatalogSynced =>
      'Laufzeit-Tool-Katalog synchronisiert';

  @override
  String get toolbarPlanAwaitingNoExecTools =>
      'Plan wartet auf Freigabe, Ausführungstools bleiben verborgen';

  @override
  String get toolbarPlanReviewBeforeResume =>
      'Abgeschlossene Schritte, Artefakte und Todos prüfen';

  @override
  String get toolbarPlanApprovedExecOpen =>
      'Plan freigegeben, Ausführungstools verfügbar';

  @override
  String get toolbarPlanOnlyPlanningExitAllowed =>
      'Nur Planungstools verfügbar, bis der Ausführungsplan bereit ist';

  @override
  String get toolbarPlanOnlyPlanningOnly =>
      'Aktuell nur Planungstools verfügbar';

  @override
  String get toolbarModeJustSwitched =>
      'Modus gerade gewechselt, Katalog wird nächste Runde aktualisiert';

  @override
  String get toolbarChatModeNoTools =>
      'Im Chat-Modus sind aktuell keine Tools verfügbar';

  @override
  String get toolbarChatModeAllTools =>
      'Chat-Modus zeigt den vollständigen Laufzeit-Katalog';

  @override
  String get toolbarRuntimeNoSnapshotPrompt =>
      'Noch kein Laufzeit-Snapshot. Bitte zuerst eine Anfrage senden.';

  @override
  String get toolbarGateNoReason => 'Keine Gate-Begründung verfügbar';

  @override
  String get toolbarGateProtocolUnsupportedSwitchPlan =>
      'Modellprotokoll unterstützt keine Tool-Aufrufe. Klicken zum Wechsel in Planmodus.';

  @override
  String get toolbarGateChatActiveSwitchPlan =>
      'Chat-Modus aktiv. Klicken zum Wechsel in Planmodus.';

  @override
  String get toolbarGatePlanActiveSwitchChat =>
      'Planmodus aktiv. Klicken zum Wechsel in Chat-Modus.';

  @override
  String get toolbarGateProtocolUnsupportedSwitchChat =>
      'Modellprotokoll unterstützt keine Tool-Aufrufe. Planmodus kann Schritte organisieren, aber keine Ausführung. Klicken zum Wechsel in Chat-Modus.';

  @override
  String get toolbarGatePlanJustSwitchedToChat =>
      'Planmodus gerade gewechselt. Laufzeittools aktualisieren sich nächste Runde. Klicken für Chat-Modus.';

  @override
  String get toolbarGatePlanAwaitingSwitchChat =>
      'Plan wartet auf Freigabe. Ausführungstools bleiben bis zur Freigabe verborgen. Klicken für Chat-Modus.';

  @override
  String get toolbarGatePlanReviewSwitchChat =>
      'Plan zu prüfen. Vor dem Fortsetzen abgeschlossene Schritte, Artefakte und Todos prüfen. Klicken für Chat-Modus.';

  @override
  String get toolbarGatePlanExecutingSwitchChat =>
      'Plan wird ausgeführt. Laufzeittools laut aktuellem Katalog verfügbar. Klicken für Chat-Modus.';

  @override
  String get toolbarGatePlanModeSwitchChat =>
      'Planmodus aktiv. Erst planen, dann nach Freigabe ausführen. Klicken für Chat-Modus.';

  @override
  String get toolbarFilesShow => 'Projektdateien';

  @override
  String get toolbarFilesHide => 'Dateien ausblenden';

  @override
  String get toolbarRuntimeModeChat => 'Chat-Modus';

  @override
  String get toolbarRuntimeModeChatCompact => 'Chat';

  @override
  String get toolbarRuntimeModePlan => 'Planmodus';

  @override
  String get toolbarRuntimeModePlanCompact => 'Plan';

  @override
  String get toolbarRuntimeModePlanAwaiting => 'Plan wartet auf Freigabe';

  @override
  String get toolbarRuntimeModePlanAwaitingCompact => 'Wartet auf Freigabe';

  @override
  String get toolbarRuntimeModePlanReview => 'Plan zu prüfen';

  @override
  String get toolbarRuntimeModePlanReviewCompact => 'Zu prüfen';

  @override
  String get toolbarRuntimeModePlanExecution => 'Plan-Ausführung';

  @override
  String get toolbarRuntimeModePlanExecutionCompact => 'Ausführen';

  @override
  String get toolbarRuntimeModePlanDrafting => 'Plan-Entwurf';

  @override
  String get toolbarRuntimeModePlanDraftCompact => 'Entwurf';

  @override
  String toolbarRuntimeNotices(int count) {
    return '$count Laufzeit-Hinweise';
  }

  @override
  String toolbarMcpLazyLoading(int loaded, int total) {
    return 'MCP $loaded/$total geladen';
  }

  @override
  String snackToolSearchLoaded(int loaded, int total) {
    return 'ToolSearch hat $loaded/$total MCP-Tool(s) geladen';
  }

  @override
  String get snackToolSearchLoadedAction => 'Liste anzeigen';

  @override
  String get snackToolSearchLoadedDialogTitle =>
      'Von ToolSearch geladene MCP-Tools';

  @override
  String get snackToolSearchLoadedDialogClose => 'Schließen';

  @override
  String get snackToolSearchLoadedCopyAction => 'select: kopieren';

  @override
  String get snackToolSearchLoadedCopiedToast => 'Kopiert';

  @override
  String get snackToolSearchLoadedClearAction => 'Geladene Liste leeren';

  @override
  String get snackToolSearchLoadedClearedToast => 'Geladene Liste geleert';

  @override
  String get snackToolSearchLoadedGroupOther => 'Andere (kein Server-Präfix)';

  @override
  String get snackToolSearchLoadedCopyGroupAction => 'Gesamte Gruppe kopieren';

  @override
  String get snackToolSearchLoadedTabLoaded => 'Geladen';

  @override
  String get snackToolSearchLoadedTabHistory => 'Verlauf';

  @override
  String get snackToolSearchLoadedHistoryEmpty =>
      'Noch keine ToolSearch-Ladevorgänge in dieser Sitzung';

  @override
  String get snackToolSearchLoadedHistoryQueryPrefix => 'Anfrage: ';

  @override
  String get snackToolSearchLoadedFilterHint => 'Nach Name filtern…';

  @override
  String get snackToolSearchLoadedHistoryFilterHint =>
      'Nach Name oder Anfrage filtern…';

  @override
  String get snackToolSearchLoadedSourceAi => 'KI-Sitzung';

  @override
  String get snackToolSearchLoadedSourceHarness => 'Harness-Phase';

  @override
  String get snackToolSearchLoadedReplayedToast =>
      'ToolSearch mit vorheriger Auswahl erneut ausgelöst';

  @override
  String get snackToolSearchLoadedReplayPendingToast =>
      'Wird gesendet — auf Abbrechen tippen, um zu stoppen';

  @override
  String get snackToolSearchLoadedReplayCancelAction => 'Abbrechen';

  @override
  String get snackToolSearchLoadedReplayCancelledToast =>
      'Versand abgebrochen — Composer geleert';

  @override
  String get snackToolSearchLoadedSourceFilterAll => 'Alle';

  @override
  String get snackToolSearchLoadedSourceFilterAi => 'Nur KI';

  @override
  String get snackToolSearchLoadedSourceFilterHarness => 'Nur Harness';

  @override
  String snackToolSearchLoadedSummary(int queries, int tools) {
    return '$tools MCP-Tool(s) aus $queries Anfrage(n) in dieser Sitzung geladen';
  }

  @override
  String get snackToolSearchLoadedHistoryReplayAction =>
      'Diese Charge als select:… kopieren';

  @override
  String get snackToolSearchLoadedHistoryClearAction => 'Verlauf leeren';

  @override
  String get snackToolSearchLoadedHistoryExportTooltip => 'Verlauf exportieren';

  @override
  String get snackToolSearchLoadedHistoryExportCsv => 'Als CSV kopieren';

  @override
  String get snackToolSearchLoadedHistoryExportMarkdown =>
      'Als Markdown kopieren';

  @override
  String get snackToolSearchLoadedHistoryExportJson => 'Als JSON kopieren';

  @override
  String get snackToolSearchLoadedHistoryExportSaveCsv => 'Als CSV speichern…';

  @override
  String get snackToolSearchLoadedHistoryExportSaveMarkdown =>
      'Als Markdown speichern…';

  @override
  String get snackToolSearchLoadedHistoryExportSaveJson =>
      'Als JSON speichern…';

  @override
  String get snackToolSearchLoadedHistoryExportCsvHint =>
      'Tabellenkalkulationsfreundlich; eine Zeile pro Anfrage.';

  @override
  String get snackToolSearchLoadedHistoryExportMarkdownHint =>
      'GitHub-Stil-Tabelle; gut für Issues und Docs.';

  @override
  String get snackToolSearchLoadedHistoryExportJsonHint =>
      'Strukturierte Daten; kann wieder in OpenHand importiert werden.';

  @override
  String get toolSearchLoadedHistoryImportTooltip => 'JSON-Dump importieren';

  @override
  String get toolSearchLoadedHistoryImportDialogTitle =>
      'ToolSearch-Verlaufsimport-Vorschau';

  @override
  String toolSearchLoadedHistoryImportDialogCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge',
      one: '1 Eintrag',
      zero: 'keine Einträge',
    );
    return '$_temp0';
  }

  @override
  String get toolSearchLoadedHistoryImportDialogEmpty =>
      'Keine Einträge in der Datei gefunden.';

  @override
  String get toolSearchLoadedHistoryImportDialogClose => 'Schließen';

  @override
  String snackToolSearchLoadedHistoryExportSavedToast(int count, String path) {
    return '$count Einträge in $path gespeichert';
  }

  @override
  String snackToolSearchLoadedHistoryExportSaveFailedToast(String error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String get snackToolSearchLoadedHistoryExportRevealAction =>
      'Im Finder anzeigen';

  @override
  String get snackToolSearchLoadedHistoryExportEmptyToast =>
      'Verlauf nach Filterung leer; nichts zu exportieren.';

  @override
  String snackToolSearchLoadedHistoryExportedToast(int count) {
    return '$count Verlaufseinträge in die Zwischenablage kopiert.';
  }

  @override
  String get snackToolSearchLoadedHistoryClearedToast => 'Ladeverlauf geleert';

  @override
  String get mcpLazyLoadingViewLoadedAction =>
      'Geladene Liste der aktuellen Sitzung anzeigen';

  @override
  String get mcpToolSearchExportLastDirResetAction =>
      'Gespeicherten Exportordner zurücksetzen';

  @override
  String get mcpToolSearchExportLastDirResetToast =>
      'Gespeicherter Exportordner gelöscht';

  @override
  String get mcpLazyLoadingNoActiveSession => 'Derzeit keine aktive Sitzung';

  @override
  String toolbarPlanStepsCompleted(int completed, int total) {
    return '$completed/$total Schritte abgeschlossen';
  }

  @override
  String get mdlEdEnterAValidBaseUrlFirst =>
      'Zuerst gültige Basis-URL eingeben';

  @override
  String get mdlEdNoModelsFoundFromThisProvider =>
      'Bei diesem Anbieter wurden keine Modelle gefunden.';

  @override
  String get mdlEdProviderName => 'Anbietername';

  @override
  String get mdlEdOptionalEGDeepseekLocalOllama =>
      'Optional, z. B. DeepSeek, lokales Ollama';

  @override
  String get mdlEdCurrentlyActiveModel => 'Derzeit aktives Modell';

  @override
  String get mdlEdClickToSetAsActiveModel =>
      'Anklicken, um als aktives Modell festzulegen';

  @override
  String get mdlEdTapScanModelsToDiscoverModels =>
      'Tippen Sie auf „Modelle scannen“, um Modelle automatisch zu entdecken, oder fügen Sie sie unten manuell hinzu.';

  @override
  String get mdlEdActiveModelId => 'Aktive Modell-ID';

  @override
  String get mdlEdTheModelUsedForConversationsSelect =>
      'Das Modell, das für Konversationen verwendet wird. Aus der obigen Liste auswählen oder direkt eingeben.';

  @override
  String get mdlEdMaxContextTokens => 'Max. Kontext-Token';

  @override
  String get mdlEdOptionalLimitsTheHistorySliceUsed =>
      'Optional. Begrenzt den Verlaufsabschnitt, der bei der Kompression verwendet wird.';

  @override
  String get mdlEdEnterAWholeNumberGreaterThan => 'Ganzzahl größer 0 eingeben';

  @override
  String get mdlEdRequestMethod => 'Anfragemethode';

  @override
  String get mdlEdOutputMode => 'Ausgabemodus';

  @override
  String get mdlEdStreaming => 'Streaming';

  @override
  String get mdlEdNonStreaming => 'Nicht-Streaming';

  @override
  String get mdlEdMaxOutputTokens => 'Max. Ausgabe-Token';

  @override
  String get mdlEdOptionalUsesAdapterDefaultIfUnset =>
      'Optional. Verwendet den Adapter-Standard, wenn nicht gesetzt.';

  @override
  String get mdlEdTemperature => 'Temperatur';

  @override
  String get mdlEd0020Default0 => '0,0 ~ 2,0, Standard 0,7';

  @override
  String get mdlEdEnterANumberBetween00 => 'Zahl zwischen 0,0 und 2,0 eingeben';

  @override
  String get mdlEdCustomHeaders => 'Benutzerdefinierte Header';

  @override
  String get mdlEdAdd => 'Hinzufügen';

  @override
  String get mdlEdNoCustomHeadersTapAddTo =>
      'Keine benutzerdefinierten Header. Tippen Sie auf „Hinzufügen“, um einen zu erstellen.';

  @override
  String get mdlEdHeaderName => 'Header-Name';

  @override
  String get mdlEdHeaderValue => 'Header-Wert';

  @override
  String get mdlEdEditModelProfile => 'Modellprofil bearbeiten';

  @override
  String get mdlEdDisplayName => 'Anzeigename';

  @override
  String get mdlEdOptionalShownInTheUi =>
      'Optional, in der Oberfläche angezeigt';

  @override
  String get mdlEdDescription => 'Beschreibung';

  @override
  String get mdlEdMultimodalSupport => 'Multimodal-Unterstützung';

  @override
  String get mdlEdAutoDetect => 'Auto erkennen';

  @override
  String get mdlEdYes => 'Ja';

  @override
  String get mdlEdNo => 'Nein';

  @override
  String get mdlEdSupportsAttachments => 'Unterstützt Anhänge';

  @override
  String get mdlEdReasoningEcho => 'Denkverlauf einbeziehen';

  @override
  String get mdlEdReasoningEchoHint =>
      'Legt fest, ob frühere Denk-/Reasoning-Inhalte für dieses Modell erneut in den Prompt-Verlauf eingespeist werden.';

  @override
  String get mdlEdSupportedModalities => 'Unterstützte Modalitäten';

  @override
  String get mdlEdText => 'Text';

  @override
  String get mdlEdImage => 'Bild';

  @override
  String get mdlEdVideo => 'Video';

  @override
  String get mdlEdAudio => 'Audio';

  @override
  String get mdlEdGenerationCapabilities => 'Generierungsfähigkeiten';

  @override
  String get mdlEdPdf => 'PDF';

  @override
  String get mdlEdPpt => 'PPT';

  @override
  String get mdlEdTokenLimits => 'Token-Limits';

  @override
  String get mdlEdContextLength => 'Kontextlänge';

  @override
  String get mdlEdSummaryLength => 'Zusammenfassungslänge';

  @override
  String get mdlEdOutputLength => 'Ausgabelänge';

  @override
  String get mdlEdThinkingLength => 'Denklänge';

  @override
  String get mdlEdTokenPricingUsd1mTokensLeave =>
      'Token-Preise (USD / 1 Mio. Token, leer lassen, wenn nicht festgelegt)';

  @override
  String get mdlEdInput => 'Eingabe';

  @override
  String get mdlEdOutput => 'Ausgabe';

  @override
  String get mdlEdCacheRead => 'Cache-Lesen';

  @override
  String get mdlEdCacheWrite => 'Cache-Schreiben';

  @override
  String get mdlEdOpenRouterMetadataOverrides =>
      'OpenRouter-Metadatenüberschreibungen';

  @override
  String get mdlEdCanonicalSlug => 'Kanonischer Modell-Slug';

  @override
  String get mdlEdHuggingFaceId => 'Hugging-Face-Modell-ID';

  @override
  String get mdlEdKnowledgeCutoff => 'Wissensstand';

  @override
  String get mdlEdExpirationDate => 'Ablaufdatum';

  @override
  String get mdlEdSupportedParametersCsv => 'Unterstützte Parameter';

  @override
  String get mdlEdSupportedParametersCsvHint =>
      'Beispiel: input, model, input_type, truncate';

  @override
  String get mdlEdDefaultParametersJson => 'Standardparameter';

  @override
  String get mdlEdDefaultParametersJsonHint =>
      'Beispiel: encoding_format: float';

  @override
  String get mdlEdOpenRouterRawMetadata => 'OpenRouter-Rohmetadaten';

  @override
  String get mdlEdOpenRouterRawMetadataFields =>
      'Enthält id, canonical_slug, hugging_face_id, created, architecture, supported_parameters, default_parameters, supported_voices, knowledge_cutoff, expiration_date und links';

  @override
  String get mdlEdReset => 'Zurücksetzen';

  @override
  String get mdlEdCancel => 'Abbrechen';

  @override
  String get mdlEdOk => 'OK';

  @override
  String get tlCallDir => 'Verzeichnis';

  @override
  String get tlCallElapsed => 'Verstrichen';

  @override
  String get tlCallExit => 'Beenden';

  @override
  String get tlCallToolInput => 'Werkzeugeingabe';

  @override
  String get tlCallCommand => 'Befehl';

  @override
  String get tlCallArguments => 'Argumente';

  @override
  String get tlCallToolOutput => 'Werkzeugausgabe';

  @override
  String get tlCallNoOutputYet => 'Noch keine Ausgabe';

  @override
  String get tlCallResult => 'Ergebnis';

  @override
  String get tlCallStdout => 'stdout';

  @override
  String get tlCallStderr => 'stderr';

  @override
  String get tlCallArgumentsConstructing => 'Argumente werden aufgebaut…';

  @override
  String get tlCallArgumentsConstructingHint =>
      'Die Argumente werden noch vom Modell gestreamt; die Karte wechselt nach Fertigstellung in den Normalzustand.';

  @override
  String get tlCallCollectedParameters => 'Erfasst';

  @override
  String get tlCallNoParametersYet => 'Noch keine Argumente erkannt';

  @override
  String get tlCallSubmitting => 'Wird gesendet…';

  @override
  String get tlCallSubmittingHint =>
      'Argumente erfasst; Übergabe an den Executor';

  @override
  String get tlCallThereIsNoToolOutputYet => 'Noch keine Werkzeugausgabe.';

  @override
  String get tlCallViewInDialog => 'Im Dialog anzeigen';

  @override
  String get tlCallEmptyContent => 'Leerer Inhalt';

  @override
  String get fileMutationSection => 'Dateiänderungen';

  @override
  String fileMutationFilesChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien geändert',
      one: '1 Datei geändert',
    );
    return '$_temp0';
  }

  @override
  String fileMutationFilesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien',
      one: '1 Datei',
    );
    return '$_temp0';
  }

  @override
  String get fileMutationUndoAll => 'Alle rückgängig';

  @override
  String get fileMutationRefresh => 'Aktualisieren';

  @override
  String get fileMutationCopyAllDiff => 'Alle Diffs kopieren';

  @override
  String get fileMutationCopyAllDiffDone =>
      'Alle Diffs in die Zwischenablage kopiert';

  @override
  String get fileMutationRevealLedger =>
      'ledger.jsonl im Dateimanager anzeigen';

  @override
  String get fileMutationCopyPath => 'Dateipfad kopieren';

  @override
  String get fileMutationPathCopied => 'Pfad kopiert';

  @override
  String fileMutationRevealMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Änderungen',
      one: 'Änderung',
    );
    return '$count weitere $_temp0 ausgeblendet — antippen für nächste Charge';
  }

  @override
  String get fileMutationRevealAll => 'Alle anzeigen';

  @override
  String get fileMutationHistoryInspector => 'Verlaufs-Inspektor';

  @override
  String get fileMutationHistoryInspectorTitle =>
      'Dateiänderungsverlauf der Sitzung';

  @override
  String get fileMutationHistoryInspectorFilterHint => 'Nach Pfad filtern…';

  @override
  String get fileMutationHistoryInspectorEmpty =>
      'Keine Dateiänderungen entsprechen dem Filter.';

  @override
  String get fileMutationHistoryInspectorZoomIn =>
      'Auf diesen Pfad fokussieren';

  @override
  String get fileMutationHistoryInspectorZoomOut => 'Alle Pfade anzeigen';

  @override
  String get fileMutationUndone => 'Rückgängig';

  @override
  String get fileMutationCascadeUndone => 'Kaskadiert rückgängig';

  @override
  String get fileMutationUndoThis => 'Diese Änderung rückgängig machen';

  @override
  String get fileMutationRedo => 'Wiederherstellen';

  @override
  String get fileMutationUndoFailed => 'Rückgängig fehlgeschlagen';

  @override
  String get fileMutationRedoFailed => 'Wiederherstellen fehlgeschlagen';

  @override
  String get fileMutationSnapshotUnavailable =>
      'Inhalts-Snapshot nicht verfügbar';

  @override
  String get tlCallTool => 'Werkzeug';

  @override
  String get tlCallSkill => 'Fähigkeit';

  @override
  String get tlCallStopped => 'Gestoppt';

  @override
  String get tlCallStopRequest => 'Diesen Werkzeugaufruf abbrechen';

  @override
  String get tlCallBlocked => 'Blockiert';

  @override
  String get tlCallRejected => 'Abgelehnt';

  @override
  String get tlCallInvalid => 'Ungültig';

  @override
  String get tlCallToolCall => 'Werkzeugaufruf';

  @override
  String get tlCallRunning => 'Läuft';

  @override
  String get tlCallSucceeded => 'Erfolgreich';

  @override
  String get tlCallDenied => 'Verweigert';

  @override
  String get tlCallTimedOut => 'Zeitüberschreitung';

  @override
  String get tlCallFailed => 'Fehlgeschlagen';

  @override
  String get tlCallToolIsRunningWaitingForOutput =>
      'Werkzeug läuft. Warten auf Ausgabe …';

  @override
  String get tlCallExpandToInspectToolOutput =>
      'Erweitern, um die Werkzeugausgabe zu prüfen';

  @override
  String get tlCallSelfLearning => 'Selbstlernen';

  @override
  String get tlCallNudgeRecovered => 'Nudge wiederhergestellt';

  @override
  String get tlCallProfileChanges => 'Profiländerungen';

  @override
  String get tlCallMemoryChanges => 'Speicheränderungen';

  @override
  String get tlCallSkillChanges => 'Skill-Änderungen';

  @override
  String get tlCallProfileDiff => 'Profilunterschied';

  @override
  String get tlCallNoChanges => 'Keine Änderungen';

  @override
  String get tlCallUnnamed => '(unbenannt)';

  @override
  String get tlCallJustNow => 'gerade eben';

  @override
  String get sessMetaCacheHitTrend => 'CACHE-TREFFERQUOTE-TREND';

  @override
  String get sessMetaCacheHitLast => 'aktuell';

  @override
  String get sessMetaCacheHitAvg => 'Schnitt';

  @override
  String get sessMetaCacheHitMax => 'max';

  @override
  String get sessMetaCacheHitOverlayOn => 'Andere Formel überlagern';

  @override
  String get sessMetaCacheHitOverlayOff => 'Überlagerung ausblenden';

  @override
  String get sessMetaCacheHitFormulaClaude => 'Claude-Formel';

  @override
  String get sessMetaCacheHitFormulaOpenAi => 'OpenAI-Formel';

  @override
  String sessMetaCacheHitPoint(int index) {
    return 'Runde $index';
  }

  @override
  String get sessMetaMessages => 'Nachrichten';

  @override
  String get sessMetaPromptBuilds => 'Prompt-Aufbauten';

  @override
  String get sessMetaCompressions => 'Kompressionen';

  @override
  String get sessMetaTotalTokens => 'Gesamt-Token';

  @override
  String get sessMetaMode => 'Modus';

  @override
  String get sessMetaRuntimeTools => 'Laufzeit-Werkzeuge';

  @override
  String get sessMetaPending => 'Ausstehend';

  @override
  String get sessMetaCurrentSessionMetadata => 'Aktuelle Sitzungsmetadaten';

  @override
  String get sessMetaSessionOverview => 'Sitzungsübersicht';

  @override
  String get sessMetaExtendedMetadata => 'Erweiterte Metadaten';

  @override
  String get sessMetaStatistics => 'Statistik';

  @override
  String get sessMetaUser => 'Benutzer';

  @override
  String get sessMetaAssistant => 'Assistent';

  @override
  String get sessMetaTool => 'Werkzeug';

  @override
  String get sessMetaSkill => 'Fähigkeit';

  @override
  String get sessMetaCompression => 'Kompression';

  @override
  String get sessMetaEnvironment => 'Umgebung';

  @override
  String get sessMetaCommandPolicy => 'Befehlsrichtlinie';

  @override
  String get sessMetaPromptMetadataIsNotAvailableYet =>
      'Prompt-Metadaten sind noch nicht verfügbar.';

  @override
  String get sessMetaWriteConfirmation => 'Schreibbestätigung';

  @override
  String get sessMetaRequired => 'Erforderlich';

  @override
  String get sessMetaNotRequired => 'Nicht erforderlich';

  @override
  String get sessMetaAllowRules => 'Erlauben-Regeln';

  @override
  String get sessMetaThereAreNoSurfacedAllowCommand =>
      'Es gibt keine sichtbaren Erlauben-Befehlsregeln.';

  @override
  String get sessMetaRuntimeOrchestration => 'Laufzeit-Orchestrierung';

  @override
  String get sessMetaStateSource => 'Zustandsquelle';

  @override
  String get sessMetaGeneratedFromTheCurrentModelMcp =>
      'Erzeugt aus aktuellem Modell, MCP/Skills und Planzustand';

  @override
  String get sessMetaTheLastPersistedRuntimeSnapshot =>
      'Der zuletzt persistierte Laufzeit-Snapshot';

  @override
  String get sessMetaToolCatalogState => 'Werkzeugkatalog-Zustand';

  @override
  String get sessMetaGateReason => 'Gate-Grund';

  @override
  String get sessMetaRuntimeToolCount => 'Anzahl Laufzeit-Werkzeuge';

  @override
  String get sessMetaRefreshesNextRound =>
      'Aktualisiert sich in der nächsten Runde';

  @override
  String get sessMetaRuntimeNotices => 'Laufzeit-Hinweise';

  @override
  String get sessMetaCurrentRuntimeTools => 'Aktuelle Laufzeit-Werkzeuge';

  @override
  String get sessMetaTaskTracking => 'Aufgabenverfolgung';

  @override
  String get sessMetaCurrentTodos => 'Aktuelle Todos';

  @override
  String get sessMetaPlanRecords => 'Planeinträge';

  @override
  String get sessMetaTodowriteReminder => 'TodoWrite-Erinnerung';

  @override
  String get sessMetaTriggered => 'Ausgelöst';

  @override
  String get sessMetaNotTriggered => 'Nicht ausgelöst';

  @override
  String get sessMetaUnavailable => 'Nicht verfügbar';

  @override
  String get sessMetaReminderReason => 'Erinnerungsgrund';

  @override
  String get sessMetaPlanHistory => 'Planverlauf';

  @override
  String get sessMetaRecentErrors => 'Kürzliche Fehler';

  @override
  String get sessMetaThereAreNoSessionErrorsTo =>
      'Keine Sitzungsfehler zur Überprüfung.';

  @override
  String get sessMetaLastPromptMetadata => 'Letzte Prompt-Metadaten';

  @override
  String get sessMetaClose => 'Schließen';

  @override
  String get sessMetaPendingApproval => 'Genehmigung ausstehend';

  @override
  String get sessMetaInProgress => 'In Bearbeitung';

  @override
  String get sessMetaCompleted => 'Abgeschlossen';

  @override
  String get sessMetaFailed => 'Fehlgeschlagen';

  @override
  String get sessMetaCancelled => 'Abgebrochen';

  @override
  String get sessMetaCreated => 'Erstellt';

  @override
  String get sessMetaUpdated => 'Aktualisiert';

  @override
  String get sessMetaErrorDetail => 'Fehlerdetail';

  @override
  String get commonDetails => 'Details';

  @override
  String get commonCopy => 'Kopieren';

  @override
  String get commonViewDetails => 'Details anzeigen';

  @override
  String get commonCopiedToClipboard => 'In die Zwischenablage kopiert';

  @override
  String get structuredErrorWhy => 'Warum:';

  @override
  String get structuredErrorTry => 'Vorschlag:';

  @override
  String get structuredErrorServerSays => 'Serverantwort:';

  @override
  String get structuredErrorRaw => 'Rohfehler:';

  @override
  String get sessMetaPresented => 'Angezeigt';

  @override
  String get sessMetaThisSessionEndedEarlyRetryThe =>
      'Diese Sitzung wurde vorzeitig beendet. Anfrage erneut versuchen oder mit einer spezifischeren Anweisung fortfahren.';

  @override
  String get sessMetaToolCallsStoppedForSafety =>
      'Werkzeugaufrufe aus Sicherheitsgründen gestoppt';

  @override
  String get sessMetaOpenhandStoppedThisSessionForSafety =>
      'OpenHand hat diese Sitzung aus Sicherheitsgründen nach zu vielen aufeinanderfolgenden Werkzeugrunden gestoppt. Dieser Stopp erfolgte im Sitzungscontroller, bevor das nächste Werkzeug laufen konnte – nicht, weil eine bestimmte Werkzeugausführung fehlschlug. Bitten Sie den Assistenten, den aktuellen Fortschritt zusammenzufassen, oder geben Sie einen spezifischeren nächsten Schritt vor.';

  @override
  String get sessMetaResponseInterrupted => 'Antwort unterbrochen';

  @override
  String get sessMetaTheResponseWasInterruptedWhileStreaming =>
      'Die Antwort wurde während des Streamings unterbrochen, und diese Sitzung wurde gestoppt. Anfrage erneut versuchen oder mit einer neuen Nachricht fortfahren.';

  @override
  String get sessMetaRequestFailed => 'Anfrage fehlgeschlagen';

  @override
  String get sessMetaTheRequestFailedBeforeTheAssistant =>
      'Die Anfrage schlug fehl, bevor der Assistent fortfahren konnte. Konfiguration überprüfen und erneut versuchen oder eine neue Nachricht senden.';

  @override
  String get sessMetaContinuationFailed => 'Fortsetzung fehlgeschlagen';

  @override
  String get sessMetaTheSessionFailedWhileRequestingThe =>
      'Die Sitzung schlug fehl, während sie nach einer Fortsetzung der Ausführung die nächste Assistentenrunde anforderte. Abgeschlossene Schritte und Werkzeugergebnisse wurden bewahrt. Antworten Sie mit „continue/retry“, oder prüfen Sie die Konfiguration und versuchen Sie es erneut.';

  @override
  String get sessMetaSafetyStop => 'Sicherheitsstopp';

  @override
  String get sessMetaStreamError => 'Stream-Fehler';

  @override
  String get sessMetaRequestError => 'Anfragefehler';

  @override
  String get sessMetaContinuationError => 'Fortsetzungsfehler';

  @override
  String get sessMetaToolExecutionError => 'Werkzeugausführungsfehler';

  @override
  String get sessMetaCompressionError => 'Kompressionsfehler';

  @override
  String get sessMetaPromptBlocked => 'Prompt blockiert';

  @override
  String get sessMetaTitleGenerationError => 'Fehler bei der Titelerzeugung';

  @override
  String get sessMetaSessionError => 'Sitzungsfehler';

  @override
  String get auditNoData => 'Keine Daten';

  @override
  String get auditCopyJson => 'JSON kopieren';

  @override
  String get auditCopiedToClipboard => 'In die Zwischenablage kopiert';

  @override
  String get auditMessageAudit => 'Nachrichten-Audit';

  @override
  String get auditClose => 'Schließen';

  @override
  String get auditOverview => 'Übersicht';

  @override
  String get auditMessageId => 'Nachrichten-ID';

  @override
  String get auditSessionId => 'Sitzungs-ID';

  @override
  String get auditRole => 'Rolle';

  @override
  String get auditKind => 'Art';

  @override
  String get auditCharacterCount => 'Zeichenanzahl';

  @override
  String get auditStreaming => 'Streaming';

  @override
  String get auditDeleted => 'Gelöscht';

  @override
  String get auditHasError => 'Hat Fehler';

  @override
  String get auditTiming => 'Zeitsteuerung';

  @override
  String get auditStartedCreated => 'Begonnen / Erstellt';

  @override
  String get auditEnded => 'Beendet';

  @override
  String get auditDurationMs => 'Dauer (ms)';

  @override
  String get auditModelTokens => 'Modell & Token';

  @override
  String get auditModelId => 'Modell-ID';

  @override
  String get auditModelLabel => 'Modellbezeichnung';

  @override
  String get auditTotalTokens => 'Gesamt-Token';

  @override
  String get auditCacheHitRatio => 'Cache-Trefferquote';

  @override
  String get auditPromptTokens => 'Prompt-Token';

  @override
  String get auditCompletionTokens => 'Antwort-Token';

  @override
  String get auditTokenBreakdown => 'Token-Aufschlüsselung';

  @override
  String get auditError => 'Fehler';

  @override
  String get auditContent => 'Inhalt';

  @override
  String get auditFullComposedPromptThatWasActually =>
      'Vollständiger zusammengestellter Prompt, der für diese Runde tatsächlich an die KI gesendet wurde (Systemanweisungen, Werkzeugkatalog, Speicher, Verlauf und Nutzereingabe).';

  @override
  String get auditWaitingForComposedPromptInjectionAuto =>
      'Warten auf Einspeisung des zusammengestellten Prompts (aktualisiert sich während des Streamings automatisch).';

  @override
  String get auditUserRawInput => 'Roh-Nutzereingabe';

  @override
  String get auditStructuredPromptTurns => 'Strukturierte Prompt-Runden';

  @override
  String get auditNone => 'Keine';

  @override
  String get auditPromptMetadata => 'Prompt-Metadaten';

  @override
  String get auditRequest => 'Anfrage';

  @override
  String get auditMethod => 'Methode';

  @override
  String get auditHeaders => 'Header';

  @override
  String get auditNotCapturedEnableSettingsAiTelemetry =>
      'Nicht erfasst (Einstellungen → KI → Telemetrie-Debug aktivieren)';

  @override
  String get auditBodyQueryPath => 'Body / Query / Path';

  @override
  String get auditRawAiResponse => 'Rohe KI-Antwort';

  @override
  String get auditExpandRawResponse => 'Rohantwort erweitern';

  @override
  String get auditNotCapturedDebugDisabledOrResponse =>
      'Nicht erfasst: Debug deaktiviert oder Antwort nicht verfügbar';

  @override
  String get auditAttachments => 'Anhänge';

  @override
  String get auditAttachmentList => 'Anhangsliste';

  @override
  String get auditNoAttachments => 'Keine Anhänge';

  @override
  String get auditFullMetadata => 'Vollständige Metadaten';

  @override
  String get auditMessageMetadata => 'Nachrichten-Metadaten';

  @override
  String get auditSessionEnvironment => 'Sitzungsumgebung';

  @override
  String get auditEnvironmentSnapshot => 'Umgebungs-Snapshot';

  @override
  String get auditAuditSnapshotCopied => 'Audit-Snapshot kopiert';

  @override
  String get auditCopyAuditSnapshot => 'Audit-Snapshot kopieren';

  @override
  String get auditSessionMetadataSaved => 'Sitzungsmetadaten gespeichert';

  @override
  String get auditSessionAudit => 'Sitzungsaudit';

  @override
  String get auditTemplate => 'Vorlage';

  @override
  String get auditCreatedAt => 'Erstellt am';

  @override
  String get auditUpdatedAt => 'Aktualisiert am';

  @override
  String get auditMessages => 'Nachrichten';

  @override
  String get auditLastModel => 'Letztes Modell';

  @override
  String get auditTitleEditable => 'Titel (bearbeitbar)';

  @override
  String get auditSessionTitle => 'Sitzungstitel';

  @override
  String get auditSaveTitle => 'Titel speichern';

  @override
  String get auditSessionMetadataEditableJson =>
      'Sitzungsmetadaten (bearbeitbares JSON)';

  @override
  String get auditSaveWritesBackThroughTheSession =>
      'Speichern schreibt über den Sitzungscontroller mit Live-UI-Diff zurück; entfernte Schlüssel werden gelöscht.';

  @override
  String get auditSaveMetadata => 'Metadaten speichern';

  @override
  String get auditRuntimePromptMetadataReadOnly =>
      'Laufzeit-Prompt-Metadaten (schreibgeschützt)';

  @override
  String get auditUsefulForPromptConstructionTroubleshooti =>
      'Nützlich für die Fehlerbehebung der Prompt-Konstruktion; wird zur Laufzeit automatisch aktualisiert.';

  @override
  String get auditLastPromptMetadata => 'last_prompt_metadata';

  @override
  String get auditNoRuntimePromptMetadataYet =>
      'Noch keine Laufzeit-Prompt-Metadaten';

  @override
  String get auditEnvironment => 'Umgebung';

  @override
  String get auditErrorList => 'Fehlerliste';

  @override
  String get auditNoErrorsRecorded => 'Keine Fehler aufgezeichnet';

  @override
  String get auditTapARowToInspectA =>
      'Tippen Sie auf eine Zeile, um eine Nachricht zu prüfen; Löschen entfernt sie aus dem Speicher.';

  @override
  String get auditNoMessages => 'Keine Nachrichten';

  @override
  String get auditAudit => 'Prüfung';

  @override
  String get auditDelete => 'Löschen';

  @override
  String get progExpFESelectOpenedFile => 'Geöffnete Datei auswählen';

  @override
  String get progExpFEExpandSelected => 'Auswahl erweitern';

  @override
  String get progExpFECollapseAll => 'Alle einklappen';

  @override
  String get progExpFETypeASymbolNameToSearch =>
      'Geben Sie einen Symbolnamen ein, um Dateien im aktuellen Arbeitsbereich zu durchsuchen.';

  @override
  String get progExpFENoWorkspaceSymbolBackendIsAvailable =>
      'Für die aktuelle Datei ist kein Arbeitsbereichs-Symbol-Backend verfügbar.';

  @override
  String get progExpFENoMatchingWorkspaceSymbolsWereFound =>
      'Keine passenden Arbeitsbereichssymbole gefunden.';

  @override
  String get progExpFEFetchingWorkspaceSymbolsFailedConfirmTha =>
      'Das Abrufen von Arbeitsbereichssymbolen ist fehlgeschlagen. Bestätigen Sie, dass der aktive Language-Server workspace/symbol unterstützt.';

  @override
  String get progExpFEThisFileIsStillInLarge =>
      'Diese Datei befindet sich noch im Vorschaumodus für große Dateien, daher nutzt die Symbolleiste lokale Extraktion, um reaktionsfähig zu bleiben.';

  @override
  String get progExpFENoLspSymbolBackendIsAvailable =>
      'Für diese Datei ist kein LSP-Symbol-Backend verfügbar; die Symbolleiste fiel auf lokale Extraktion zurück.';

  @override
  String get progExpFETheLspServerReturnedAnEmpty =>
      'Der LSP-Server hat eine leere Symbolliste zurückgegeben.';

  @override
  String get progExpFEFetchingLspSymbolsFailedSoThe =>
      'Das Abrufen von LSP-Symbolen ist fehlgeschlagen, daher fiel die Symbolleiste auf lokale Extraktion zurück.';

  @override
  String get progExpFERenameSymbol => 'Symbol umbenennen';

  @override
  String get progExpFEReviewTheDiffForThisRename =>
      'Prüfen Sie das Diff dieser Umbenennung, bevor Sie entscheiden, ob es angewendet wird.';

  @override
  String get progExpFETheRenameWasCancelledAndNo =>
      'Die Umbenennung wurde abgebrochen, und keine Änderungen wurden angewendet.';

  @override
  String get progExpFETheSymbolAtTheCurrentCursor =>
      'Das Symbol an der aktuellen Cursorposition kann nicht umbenannt werden.';

  @override
  String get progExpFETheLanguageServerDidNotReturn =>
      'Der Language-Server gab keine anzuwendenden Edits zurück.';

  @override
  String get progExpFECodeActions => 'Code-Aktionen';

  @override
  String get progExpFENoCodeActionsAreAvailableAt =>
      'An der aktuellen Cursorposition sind keine Code-Aktionen verfügbar.';

  @override
  String get progExpFEReviewTheDiffFromThisCode =>
      'Prüfen Sie das Diff dieser Code-Aktion, bevor Sie sie anwenden.';

  @override
  String get progExpFEIfTheLanguageServerCommandRequests =>
      'Wenn der Language-Server-Befehl während der Ausführung Edits anfordert, werden diese ebenfalls zuerst in der Vorschau angezeigt.';

  @override
  String get progExpFETheCodeActionWasCancelledAnd =>
      'Die Code-Aktion wurde abgebrochen, und keine Änderungen wurden angewendet.';

  @override
  String get progExpFEExecutedTheLanguageServerCommand =>
      'Language-Server-Befehl ausgeführt.';

  @override
  String get progExpFESomeLanguageServerRequestedEditsWere =>
      'Einige vom Language-Server angeforderte Edits wurden übersprungen.';

  @override
  String get progExpFEThisCodeActionDidNotReturn =>
      'Diese Code-Aktion gab keine anwendbaren Edits zurück.';

  @override
  String get progExpFEQuickFix => 'Schnellkorrektur';

  @override
  String get progExpFENoQuickFixesAreAvailableFor =>
      'Für die schwebende Diagnose sind keine Schnellkorrekturen verfügbar.';

  @override
  String get progExpFENoCodeActionsAreAvailableFor =>
      'Für die schwebende Diagnose sind keine Code-Aktionen verfügbar.';

  @override
  String get progExpFENoQuickFixesAreAvailableFor2 =>
      'Für diese Diagnosezeile sind keine Schnellkorrekturen verfügbar.';

  @override
  String get progExpFETheCurrentFileIsStillLoading =>
      'Die aktuelle Datei wird noch geladen, daher sind LSP-Aktionen noch nicht verfügbar.';

  @override
  String get progExpFEThisFileIsStillInLarge2 =>
      'Diese Datei befindet sich noch im Vorschaumodus für große Dateien. Öffnen Sie den vollen Editor, bevor Sie LSP-Navigation ausführen.';

  @override
  String get progExpFETheCurrentFileIsStillLoading2 =>
      'Die aktuelle Datei wird noch geladen, daher sind dokumentenebene Bearbeitungsaktionen noch nicht verfügbar.';

  @override
  String get progExpFEThisFileIsStillInLarge3 =>
      'Diese Datei ist noch im Vorschaumodus für große Dateien. Öffnen Sie den vollen Editor, bevor Sie formatieren.';

  @override
  String get progExpFEFormatDocument => 'Dokument formatieren';

  @override
  String get progExpFETheCurrentFileIsNotReady =>
      'Die aktuelle Datei ist noch nicht bereit. Versuchen Sie es in einem Moment erneut.';

  @override
  String get progExpFETheFormatterDidNotReturnAny =>
      'Der Formatter gab keine anzuwendenden Edits zurück.';

  @override
  String get progExpFEFormattingProducedTheSameContentSo =>
      'Die Formatierung ergab den gleichen Inhalt, daher hat sich kein Text geändert.';

  @override
  String get progExpFEGoToDefinition => 'Zur Definition gehen';

  @override
  String get progExpFENoDefinitionWasFoundAtThe =>
      'An der aktuellen Cursorposition wurde keine Definition gefunden.';

  @override
  String get progExpFEMultipleDefinitionsWereFoundChooseA =>
      'Mehrere Definitionen gefunden. Wählen Sie ein Ziel zum Navigieren.';

  @override
  String get progExpFEFindReferences => 'Verweise finden';

  @override
  String get progExpFENoReferencesWereFoundAtThe =>
      'An der aktuellen Cursorposition wurden keine Verweise gefunden.';

  @override
  String get progExpFEHoverInfo => 'Hover-Info';

  @override
  String get progExpFEThereIsNoHoverInformationAt =>
      'An der aktuellen Cursorposition gibt es keine Hover-Information.';

  @override
  String get progExpFELspBackend => 'LSP-Backend';

  @override
  String get progExpFEReResolveTheBackendForThe =>
      'Backend für aktuelle Datei neu auflösen';

  @override
  String get progExpFEInspectBackendDetails => 'Backend-Details prüfen';

  @override
  String get progExpFECloseEsc => 'Schließen (Esc)';

  @override
  String get progExpFEToggleComment => 'Kommentar umschalten';

  @override
  String get progExpFEThisLanguageDoesNotHaveA =>
      'Diese Sprache hat noch keine konfigurierte Kommentar-Strategie, daher ist das Kommentar-Umschalten nicht verfügbar.';

  @override
  String get progExpFEGoToImplementation => 'Zur Implementierung gehen';

  @override
  String get progExpFESignatureHelp => 'Signaturhilfe';

  @override
  String get progExpFEThereIsNoSignatureHelpAvailable =>
      'An der aktuellen Cursorposition ist keine Signaturhilfe verfügbar.';

  @override
  String get progExpFEPreviousMatch => 'Vorherige Übereinstimmung';

  @override
  String get progExpFENextMatch => 'Nächste Übereinstimmung';

  @override
  String get progExpFEMatchCase => 'Groß-/Kleinschreibung beachten';

  @override
  String get progExpFEShowReplace => 'Ersetzen anzeigen';

  @override
  String get progExpFEReplaceCurrent => 'Aktuelle ersetzen';

  @override
  String get progExpFEReplaceAll => 'Alle ersetzen';

  @override
  String get progExpFECurrentFileSymbols => 'Symbole der aktuellen Datei';

  @override
  String get progExpFEWorkspaceSymbols => 'Arbeitsbereichssymbole';

  @override
  String get progExpFERefreshDiagnostics => 'Diagnose aktualisieren';

  @override
  String get progExpFESymbols => 'Symbole';

  @override
  String get progExpFESymbolNavigationShiftCmdCtrlO =>
      'Symbol-Navigation (Shift+Cmd/Strg+O)';

  @override
  String get progExpFEWorkspace => 'Arbeitsbereich';

  @override
  String get progExpFEWorkspaceSymbolSearchCmdCtrlT =>
      'Arbeitsbereichs-Symbolsuche (Cmd/Strg+T)';

  @override
  String get progExpFEShowDiagnosticsForTheCurrentFile =>
      'Diagnose für aktuelle Datei anzeigen';

  @override
  String get progExpFEInspectTheLspBackendBoundTo =>
      'Das an die aktuelle Datei gebundene LSP-Backend prüfen';

  @override
  String get progExpFEDef => 'Def.';

  @override
  String get progExpFEGoToDefinitionF12CmdCtrl =>
      'Zur Definition gehen (F12 / Cmd/Strg+B)';

  @override
  String get progExpFERefs => 'Refs.';

  @override
  String get progExpFEFindReferencesShiftF12CmdCtrl =>
      'Verweise finden (Shift+F12 / Cmd/Strg+Shift+B)';

  @override
  String get progExpFEHover => 'Hover';

  @override
  String get progExpFEHoverInfoCmdCtrlI => 'Hover-Info (Cmd/Strg+I)';

  @override
  String get progExpFERename => 'Umbenennen';

  @override
  String get progExpFERenameSymbolF2 => 'Symbol umbenennen (F2)';

  @override
  String get progExpFEActions => 'Aktionen';

  @override
  String get progExpFECodeActionsCmdCtrl => 'Code-Aktionen (Cmd/Strg+.)';

  @override
  String get progExpFEFormat => 'Formatieren';

  @override
  String get progExpFENoImplementationWasFoundAtThe =>
      'An der aktuellen Cursorposition wurde keine Implementierung gefunden.';

  @override
  String get progExpFEMultipleImplementationsFoundChooseATarge =>
      'Mehrere Implementierungen gefunden. Wählen Sie ein Ziel zum Navigieren.';

  @override
  String get progExpFERefactor => 'Refaktorisieren';

  @override
  String get progExpFEReviewTheChangesBeforeApplying =>
      'Prüfen Sie die Änderungen vor dem Anwenden.';

  @override
  String get progExpFESaveFile => 'Datei speichern';

  @override
  String get progExpFECloseEditorReturnToSession =>
      'Editor schließen, zur Sitzung zurückkehren';

  @override
  String get progExpFEShowQuickFixesForThisDiagnostic =>
      'Schnellkorrekturen für diese Diagnosezeile anzeigen';

  @override
  String get progExpFELargeFilePerformanceModeIsActive =>
      'Großdatei-Leistungsmodus aktiv: virtualisierte schreibgeschützte Vorschau wird verwendet, um vollständige Dokumentlayout-Stillstände zu vermeiden.';

  @override
  String get progExpFEOpenFullEditorAnyway => 'Vollen Editor trotzdem öffnen';

  @override
  String get settingsShortcuts => 'Tastenkürzel';

  @override
  String get settingsConfigureKeyCombinationsForCommonActions =>
      'Tastenkombinationen für häufige Aktionen konfigurieren. OpenHand unterstützt derzeit bis zu vier gleichzeitige Tasten.';

  @override
  String get settingsBuiltInTools => 'Integrierte Werkzeuge';

  @override
  String get settingsCrons => 'Cron-Aufgaben';

  @override
  String get settingsControlsRetentionAndColdStartCleanup =>
      'Steuert die Aufbewahrung und Cold-Start-Bereinigung des Cron-Ausführungsverlaufs. Der Bereinigungs-Worker läuft einmal pro Kaltstart mit hartem Timeout, Single-Flight-Sperre und nur silentLog-Fehlern, sodass er nie Ressourcen leaken oder endlos schleifen kann.';

  @override
  String get settingsHermesTalker => 'Hermes Talker';

  @override
  String get settingsConfigureHermesTalkerSelfLearningEvery =>
      'Hermes Talker Selbstlernen konfigurieren: Alle 5 Minuten scannt ein System-Cron Sitzungen der letzten 7 Tage und sendet einen eingeschränkten Sub-Agenten, um Speicher und Skills im Hintergrund zu aktualisieren.';

  @override
  String get settingsEditor => 'Editor';

  @override
  String get settingsManagePerLanguageLspBackendsInstall =>
      'Pro-Sprache LSP-Backends, Installationsrouten und Download-Assistenteneinstellungen verwalten. Gespeicherte Zuordnungen werden direkt auf Editor-Navigation, Diagnose, Umbenennung und Code-Aktionen angewendet.';

  @override
  String get settingsAppData => 'App-Daten';

  @override
  String get settingsPerResponseToolCallLimit =>
      'Werkzeugaufruflimit pro Antwort';

  @override
  String get settingsSaveLimit => 'Limit speichern';

  @override
  String get settingsSequentialToolRoundLimit =>
      'Limit für aufeinanderfolgende Werkzeugrunden';

  @override
  String get settingsSessionSettings => 'Sitzungseinstellungen';

  @override
  String get settingsConfigureDefaultBehaviourForNewSessions =>
      'Standardverhalten für neue Sitzungen konfigurieren, einschließlich Timeouts, Titelabruf, Standardmodus und Berechtigungen.';

  @override
  String get settingsSendTimeoutS => 'Sende-Timeout (s)';

  @override
  String get settingsMaximumWaitTimeToEstablishThe =>
      'Maximale Wartezeit, um die HTTP-Verbindung herzustellen und die Anfrage zu senden. Standard: 60 s.';

  @override
  String get settingsSaveTimeout => 'Timeout speichern';

  @override
  String get settingsResponseTimeoutS => 'Antwort-Timeout (s)';

  @override
  String get settingsMaximumWaitForACompleteResponse =>
      'Maximale Wartezeit für eine vollständige Antwort im Nicht-Streaming-Modus. Standard: 120 s.';

  @override
  String get settingsStreamIdleTimeoutS => 'Stream-Leerlauf-Timeout (s)';

  @override
  String get settingsMaximumIdleWaitBetweenStreamChunks =>
      'Maximale Leerlauf-Wartezeit zwischen Stream-Chunks. Bei Überschreitung führt dies zu „Request timed out.“. Standard: 120 s.';

  @override
  String get settingsAutoTitle => 'Automatischer Titelabruf';

  @override
  String get settingsWhenEnabledATitleIsAutomatically =>
      'Wenn aktiviert, wird nach der ersten gültigen Textnachricht in einer neuen Sitzung automatisch ein Sitzungstitel abgerufen.';

  @override
  String get settingsTitleFetchMode => 'Titelabrufmodus';

  @override
  String get settingsTitleFetchModeDescription =>
      'Asynchron blockiert die erste Antwort nicht; synchron ruft den Titel ab, bevor die erste KI-Anfrage gesendet wird.';

  @override
  String get settingsTitleFetchModeAsync => 'Asynchron';

  @override
  String get settingsTitleFetchModeSync => 'Synchron';

  @override
  String get settingsDefaultSessionMode => 'Standard-Sitzungsmodus';

  @override
  String get settingsDefaultInteractionModeForNewSessions =>
      'Standard-Interaktionsmodus für neue Sitzungen: Chat oder Plan.';

  @override
  String get settingsChat => 'Chat';

  @override
  String get settingsPlan => 'Plan';

  @override
  String get settingsDefaultFullAccess => 'Standard-Vollzugriff';

  @override
  String get settingsWhenEnabledNewSessionsStartIn =>
      'Wenn aktiviert, starten neue Sitzungen im Vollzugriffsmodus, sodass die KI Datei- und Befehlsoperationen ohne Bestätigung pro Aktion ausführen kann.';

  @override
  String get settingsUserProfile => 'Benutzerprofil';

  @override
  String get settingsMaintainAGlobalUserProfileLanguage =>
      'Verwalten Sie ein globales Benutzerprofil (Sprachstil, Schwerpunktbereiche, Kommunikationspräferenzen). Wenn nicht leer, wird das Profil in den Systemprompt jeder Faden-Vorlage eingewoben, sodass sich die KI personalisiert anfühlt; das Selbstlernen verfeinert es schrittweise.';

  @override
  String get settingsModelProviderManagement => 'Modellanbieter-Verwaltung';

  @override
  String get settingsAddSelectTestAndMaintainModel =>
      'Modellanbieter-Konfigurationen hinzufügen, auswählen, testen und pflegen. Jeder Anbieter kann mehrere Modelle bereitstellen.';

  @override
  String get settingsCompressionTrigger => 'Kompressions-Trigger';

  @override
  String get settingsOnceTheUncompressedHistoryInA =>
      'Sobald der unkomprimierte Verlauf in einem Faden diesen Wert überschreitet, erstellt OpenHand einen neuen Zusammenfassungs-Checkpoint.';

  @override
  String get settingsToolCallOutputCompressionThreshold =>
      'Schwellwert für Werkzeugaufruf-Ausgabekompression';

  @override
  String get settingsWhenAToolCallReturnsMore =>
      'Wird nur beim Erstellen von Kompressions-Checkpoints verwendet: Historische Werkzeugergebnisse über diesem Schwellwert werden strukturiert zusammengefasst. Normale Gespräche liefern dem Modell immer vollständige Ergebnisse. Standard: 1024.';

  @override
  String get settingsDefaultsTo40IfOneAssistant =>
      'Standard 40. Wenn eine Assistenten-Antwort diese Anzahl an Werkzeugaufrufen überschreitet, sendet OpenHand eine Warnung und stoppt die Runde sicher.';

  @override
  String get settingsDefaultsTo24RoundsIfThe =>
      'Standard 24 Runden. Wenn der Assistent nach jeder Ausführung weitere Werkzeugrunden anfordert, stoppt OpenHand bei Erreichen dieses Rundenlimits, um außer Kontrolle geratene Werkzeugschleifen zu verhindern.';

  @override
  String get settingsImageSizeLimit => 'Bildgrößen-Limit';

  @override
  String get settingsDefaultsTo1mbImageAttachmentsLarger =>
      'Standard 1 MB. Bildanhänge, die größer sind als dieses Limit, werden vor dem Öffnen des Editors automatisch komprimiert und innerhalb des Limits gespeichert, um Sitzungen und Prompts kompakt zu halten.';

  @override
  String get settingsCostControl => 'Kostenkontrolle';

  @override
  String get settingsReduceTokenCostsByFreezingThe =>
      'Reduzieren Sie Token-Kosten, indem Sie das statische Prompt-Präfix stabilisieren und Cache-Hinweise auf Protokollebene anwenden. Wenn aktiviert, werden Anbieter, Modell und Denkintensität gesperrt, sobald die KI auf die erste gültige Benutzernachricht zu antworten beginnt; der Prompt Builder hält Systemanweisungen, Werkzeugkatalog, Speicher und Nutzeranweisungen möglichst stabil am Anfang; Anthropic injiziert cache_control-Breakpoints, OpenAI-kompatible Anfragen nutzen stabile Cache-Affinität und ein messages-last Body-Layout.';

  @override
  String get settingsEnableInputCache => 'Eingabecache aktivieren';

  @override
  String get settingsDisabledByDefaultWhenEnabledEvery =>
      'Standardmäßig aktiviert. Wenn deaktiviert, injiziert OpenHand keine Cache-Hinweise auf Protokollebene und nutzt keine Eingabecache-Schutzmaßnahmen wie Modellsperren. Für maximale Trefferquote sollten Werkzeuge, Skills, MCP, Speicher und Anweisungen während einer Sitzung möglichst stabil bleiben.';

  @override
  String get settingsCacheBreakpointUpdateMode =>
      'Aktualisierungsmodus für Verlaufskandidaten';

  @override
  String get settingsChooseTheSlidingUnitForThe =>
      'Stabiler Anker, vorheriges Anfrageende und aktuelles Ende haben Vorrang. Diese Einstellung steuert nur die Auswahl der verbleibenden Verlaufskandidaten.';

  @override
  String get settingsByMessageCountUserAssistant =>
      'Nach Nachrichtenanzahl (Benutzer+Assistent)';

  @override
  String get settingsByUserMessageCountOnly =>
      'Nur nach Benutzer-Nachrichtenanzahl';

  @override
  String get settingsByAccumulatedTokens => 'Nach akkumulierten Token';

  @override
  String get settingsCacheBreakpointUpdateInterval =>
      'Aktualisierungsintervall für Verlaufskandidaten';

  @override
  String get settingsDefault10MeaningDependsOnThe =>
      'Standard 10. Wird nur für automatische Verlaufskandidaten verwendet; die Einheit richtet sich nach dem obigen Modus.';

  @override
  String get settingsSave => 'Speichern';

  @override
  String get settingsCacheBreakpointCount => 'Anzahl der Cache-Breakpoints';

  @override
  String get settingsDefault4Range14Anthropic =>
      'Standard 4, Bereich 1-4. Anthropic verwendet das Budget zuerst für den stabilen System-/Werkzeuganker, das vorherige Anfrageende und das aktuelle Ende, danach für Verlaufskandidaten. Pro Anfrage sind höchstens 4 cache_control-Marker zulässig. OpenAI-kompatible Anbieter erhalten diese Marker nicht.';

  @override
  String get settingsCommandSafety => 'Befehlssicherheit';

  @override
  String get settingsControlWriteCommandConfirmationForBash =>
      'Schreib-Befehlsbestätigung für bash steuern und Verweigerungsregeln an einem Ort verwalten.';

  @override
  String get settingsWriteCommandConfirmation => 'Schreib-Befehlsbestätigung';

  @override
  String get settingsEnabledByDefaultWhenTheAi =>
      'Standardmäßig aktiviert. Wenn die KI versucht, einen schreibähnlichen bash-Befehl auszuführen, fragt OpenHand zuerst nach Ihrer Bestätigung.';

  @override
  String get settingsAllowCommandList => 'Erlaubte Befehlsliste';

  @override
  String get settingsMatchingWriteLikeBashCommandsSkip =>
      'Übereinstimmende schreibähnliche bash-Befehle überspringen den Bestätigungsdialog und werden sofort ausgeführt. Nur für stabile Befehlsmuster verwenden, denen Sie ausdrücklich vertrauen.';

  @override
  String get settingsAddAllowRule => 'Erlaubnisregel hinzufügen';

  @override
  String get settingsNoAllowRulesConfigured =>
      'Keine Erlaubnisregeln konfiguriert';

  @override
  String get settingsAddARuleToLetMatching =>
      'Fügen Sie eine Regel hinzu, damit übereinstimmende Schreibbefehle die Bestätigung umgehen.';

  @override
  String get settingsDenyCommandList => 'Verweigerungsbefehlsliste';

  @override
  String get settingsMatchingBashCommandsAreBlockedBefore =>
      'Übereinstimmende bash-Befehle werden vor der Ausführung blockiert und das Verweigerungsergebnis stattdessen an das Modell zurückgegeben. Unterstützt Regex und einfache Wildcards wie „rm *“.';

  @override
  String get settingsAddRule => 'Regel hinzufügen';

  @override
  String get settingsNoDenyRulesConfigured =>
      'Keine Verweigerungsregeln konfiguriert';

  @override
  String get settingsAddARuleToBlockMatching =>
      'Fügen Sie eine Regel hinzu, um übereinstimmende bash-Befehle vor der Ausführung zu blockieren.';

  @override
  String get settingsTelemetry => 'Telemetrie';

  @override
  String get settingsWhenEnabledOpenhandCapturesRawAi =>
      'Wenn aktiviert, erfasst OpenHand rohe KI-Antworten, Anfrageparameter, Zeiten und Fehler, sodass Sie sie in Nachrichten-/Sitzungs-Audit-Dialogen prüfen können.';

  @override
  String get settingsDebugMode => 'Debug-Modus';

  @override
  String get settingsOffByDefaultWhenEnabledEvery =>
      'Standardmäßig aus. Wenn aktiviert, zeigt jede Nachrichtenkarte beim Hovern/Fokussieren eine Audit-Pille, und jede Sitzungs-Toolbar zeigt eine Audit-Aktion auf Sitzungsebene.';

  @override
  String get settingsCaptureRawPayload => 'Rohnutzlast erfassen';

  @override
  String get settingsEnabledByDefaultOnlyActiveWhen =>
      'Standardmäßig aktiviert. Nur aktiv, wenn der Debug-Modus eingeschaltet ist. Hängt die rohen JSON-/SSE-Chunks zur Auditierung an die Nachrichten-Metadaten an.';

  @override
  String get settingsCaptureEnvironment => 'Umgebung erfassen';

  @override
  String get settingsOffByDefaultOnlyActiveWhen =>
      'Standardmäßig aus. Nur aktiv, wenn der Debug-Modus eingeschaltet ist. Hängt Arbeitsverzeichnis, Plattform-Details und Prozess-Umgebungsvariablen (kann Geheimnisse enthalten) an die Nachrichten-Metadaten an – mit Vorsicht aktivieren.';

  @override
  String get settingsShortcutBindings => 'Tastenkürzel-Zuweisungen';

  @override
  String get settingsClickRecordThenPressTheNew =>
      'Klicken Sie auf „Aufzeichnen“ und drücken Sie dann die neue Tastenkombination, um eine Zuweisung zu aktualisieren. Modell- und Sitzungswechsel umlaufen automatisch.';

  @override
  String get settingsShortcutRecord => 'Aufzeichnen';

  @override
  String get settingsShortcutResetToDefault => 'Auf Standard zurücksetzen';

  @override
  String get settingsShortcutMaxKeysError =>
      'OpenHand unterstützt bis zu vier gleichzeitig gedrückte Tasten.';

  @override
  String get settingsShortcutRecorderBody =>
      'Drücken Sie die neue Tastenkombination, um diese Zuweisung zu aktualisieren. OpenHand unterstützt bis zu vier gleichzeitig gedrückte Tasten.';

  @override
  String get settingsShortcutRecorderTip =>
      'Tipp: Verwenden Sie mindestens eine Nicht-Modifikatortaste, z. B. Enter, P oder eine Pfeiltaste.';

  @override
  String get settingsAutoCleanupExecutionHistory =>
      'Ausführungsverlauf automatisch bereinigen';

  @override
  String get settingsOnEveryColdStartAnAsync =>
      'Bei jedem Kaltstart läuft einmal ein asynchroner Worker, um Verlauf älter als das Aufbewahrungsfenster zu löschen. Der Worker ist Single-Flight, hat ein hartes Timeout und protokolliert Fehler still, sodass er die Oberfläche niemals blockieren oder endlos schleifen kann.';

  @override
  String get settingsEnableSelfLearning => 'Selbstlernen aktivieren';

  @override
  String get settingsWhenOffTheSchedulerSkipsEvery =>
      'Wenn aus, überspringt der Scheduler jede Hermes Talker Sitzung. Der System-Cron-Eintrag bleibt erhalten, sendet aber niemals einen Sub-Agenten.';

  @override
  String get settingsShowSelfLearningMessages =>
      'Selbstlern-Nachrichten anzeigen';

  @override
  String get settingsWhenOffSelfLearningCardsAre =>
      'Wenn aus, werden „Selbstlern“-Karten aus dem Chat-Verlauf ausgeblendet (Hintergrundlernen läuft weiter). Standard ein.';

  @override
  String get settingsToolCatalogOverview => 'Werkzeugkatalog-Übersicht';

  @override
  String get settingsResetAll => 'Alle zurücksetzen';

  @override
  String get settingsEnableAll => 'Alle aktivieren';

  @override
  String get settingsDisableAll => 'Alle deaktivieren';

  @override
  String get settingsNoBuiltInToolConfigurations =>
      'Keine integrierten Werkzeugkonfigurationen';

  @override
  String get settingsClickResetAllToRestoreThe =>
      'Klicken Sie auf „Alle zurücksetzen“, um die Standardwerkzeugliste wiederherzustellen.';

  @override
  String get settingsResetBuiltInToolConfigs =>
      'Integrierte Werkzeugkonfigurationen zurücksetzen';

  @override
  String get settingsCancel => 'Abbrechen';

  @override
  String get settingsReset => 'Zurücksetzen';

  @override
  String get settingsDeleteCustomTool => 'Benutzerdefiniertes Werkzeug löschen';

  @override
  String get settingsDelete => 'Löschen';

  @override
  String get settingsSendTimeoutSaved => 'Sende-Timeout gespeichert.';

  @override
  String get settingsResponseTimeoutSaved => 'Antwort-Timeout gespeichert.';

  @override
  String get settingsStreamIdleTimeoutSaved =>
      'Stream-Leerlauf-Timeout gespeichert.';

  @override
  String get settingsCacheBreakpointUpdateIntervalSaved =>
      'Aktualisierungsintervall für Verlaufskandidaten gespeichert';

  @override
  String get settingsCacheBreakpointCountSaved =>
      'Anzahl der Cache-Breakpoints gespeichert';

  @override
  String get settingsCacheBreakpointPositions => 'Cache-Verlaufskandidaten';

  @override
  String get settingsCacheBreakpointPositionsSaved =>
      'Cache-Verlaufskandidaten gespeichert';

  @override
  String get cacheBarTopDescription =>
      'Die farbigen Bänder zeigen nur die Prompt-Struktur. P-Pins markieren Kandidaten im Nachrichtenverlauf; der gestrichelte Pin rechts ist der Anker am aktuellen Anfrageende. Stabile und fortlaufende Endanker haben Vorrang.';

  @override
  String get cacheBarSectionSysLabel => '[0] System';

  @override
  String get cacheBarSectionDevLabel => '[1] Entwickler';

  @override
  String get cacheBarSectionToolsLabel => '[2] Werkzeuge';

  @override
  String get cacheBarSectionStateLabel => '[3s/3d] Zustand';

  @override
  String get cacheBarSectionMemoryLabel => '[4] Gedächtnis';

  @override
  String get cacheBarSectionUserInstLabel => '[4.5] Anweis.';

  @override
  String get cacheBarSectionSummaryLabel => '[5] Zusammenfassung';

  @override
  String get cacheBarSectionHistoryLabel => 'Verlauf';

  @override
  String get cacheBarSectionLatestLabel => 'Tail / neueste';

  @override
  String get cacheBarSectionSysSummary =>
      'Vorlagen-System-Anweisungen, Arbeitsbereich-Anweisungen und Laufzeitumgebungs-Snapshot (OS / cwd / Repo-Zusammenfassung).';

  @override
  String get cacheBarSectionSysCacheHint =>
      'Cache-freundlich: über Runden hinweg sehr stabil – idealer erster Breakpoint.';

  @override
  String get cacheBarSectionDevSummary =>
      'Verhaltensregeln aus dem aktiven Prompt-Template (Ausgabeformat & Schutzleitplanken).';

  @override
  String get cacheBarSectionDevCacheHint =>
      'Cache-freundlich: ändert sich innerhalb einer Sitzung selten.';

  @override
  String get cacheBarSectionToolsSummary =>
      'Eingebauter Tool-Katalog, MCP-Fähigkeiten und Skill-Lader, die das Modell aufrufen kann (mit DSML-Aufrufregeln).';

  @override
  String get cacheBarSectionToolsCacheHint =>
      'Recht stabil: Cache-Treffer wahrscheinlich, sofern sich das Tool-Register nicht ändert.';

  @override
  String get cacheBarSectionStateSummary =>
      'Sitzungs-Metadaten JSON: Zähler, To-do-Liste, Plan-Flags, Anhänge.';

  @override
  String get cacheBarSectionStateCacheHint =>
      'Volatil: Zähler ticken jede Runde – hier platzierte Caches verfehlen oft.';

  @override
  String get cacheBarSectionMemorySummary =>
      'Langzeit-Nutzergedächtnis als implizites Wissen integriert.';

  @override
  String get cacheBarSectionMemoryCacheHint =>
      'Meist stabil: ändert sich nur, wenn Speichereinträge bearbeitet werden.';

  @override
  String get cacheBarSectionUserInstSummary =>
      'Wiederverwendbare Prompt-Fragmente vom Nutzer (Anleitung auf Projektebene).';

  @override
  String get cacheBarSectionUserInstCacheHint =>
      'Stabil: wird selten bearbeitet – ein Breakpoint dahinter ist sicher.';

  @override
  String get cacheBarSectionSummarySummary =>
      'Komprimierte Zusammenfassung älterer Gespräche + jüngste Chat-Auszüge.';

  @override
  String get cacheBarSectionSummaryCacheHint =>
      'Langsam veränderlich: wird bei Komprimierungslauf aktualisiert.';

  @override
  String get cacheBarSectionHistorySummary =>
      'Vergangene Benutzer-/Assistent-/Werkzeug-Runden in der aktuellen Sitzung.';

  @override
  String get cacheBarSectionHistoryCacheHint =>
      'Nur anhängend: Breakpoints in der Mitte überstehen neue Runden am Ende.';

  @override
  String get cacheBarSectionLatestSummary =>
      'Die aktuell beantwortete Benutzernachricht (mit Anhang-Metadaten).';

  @override
  String get cacheBarSectionLatestCacheHint =>
      'Ändert sich jede Runde: Der aktuelle Endanker deckt diesen Bereich ab, während der vorherige Endanker die Kontinuität bewahrt.';

  @override
  String get cacheBarDynamicTooltip =>
      'Anker am aktuellen Anfrageende — folgt stets der neuesten Nachricht.';

  @override
  String get cacheBarDynamicSuffix => '(aktuelles Ende)';

  @override
  String get cacheBarResetEven => 'Gleichmäßig zurücksetzen';

  @override
  String get settingsAiBudgetUsdPerSession => 'Budget pro Sitzung (USD)';

  @override
  String get settingsAiBudgetUsdPerSessionBody =>
      '0 deaktiviert die Warnung. Überschreiten die kumulierten geschätzten Kosten einer Sitzung diese Obergrenze, hebt der Sitzungsmetadaten-Dialog den Gesamtwert in einer Warnfarbe hervor. Reine Soft-Erinnerung — die Konversation wird weder unterbrochen noch das Senden blockiert.';

  @override
  String get settingsAiBudgetUsdPerSessionInvalid =>
      'Bitte eine nicht negative Zahl zwischen 0 und 100000 eingeben.';

  @override
  String get settingsAiBudgetUsdPerSessionSaved =>
      'Budget pro Sitzung gespeichert';

  @override
  String sessionMetadataOverBudgetNotice(String total, String budget) {
    return 'Geschätzte Kosten $total der aktuellen Sitzung haben das Budget $budget überschritten. Reine Soft-Erinnerung — Senden ist nicht betroffen.';
  }

  @override
  String get settingsEnterAToolCallLimitGreater =>
      'Werkzeugaufruflimit größer als 0 eingeben.';

  @override
  String get settingsThePerResponseToolCallLimit =>
      'Werkzeugaufruflimit pro Antwort gespeichert.';

  @override
  String get settingsEnterASequentialToolRoundLimit =>
      'Limit für aufeinanderfolgende Werkzeugrunden größer als 0 eingeben.';

  @override
  String get settingsTheSequentialToolRoundLimitHas =>
      'Limit für aufeinanderfolgende Werkzeugrunden gespeichert.';

  @override
  String get settingsDeleteDenyRule => 'Verweigerungsregel löschen';

  @override
  String get settingsTheDenyCommandRuleHasBeen =>
      'Verweigerungs-Befehlsregel gelöscht.';

  @override
  String get settingsDeleteAllowRule => 'Erlaubnisregel löschen';

  @override
  String get settingsTheAllowCommandRuleHasBeen =>
      'Erlaubnis-Befehlsregel gelöscht.';

  @override
  String get settingsTheShortcutHasBeenUpdated => 'Tastenkürzel aktualisiert.';

  @override
  String get settingsTheEditorShortcutHasBeenUpdated =>
      'Editor-Tastenkürzel aktualisiert.';

  @override
  String get settingsSendMessage => 'Nachricht senden';

  @override
  String get settingsCollapseOrExpandComposer =>
      'Eingabefeld einklappen oder erweitern';

  @override
  String get settingsPreviousModel => 'Vorheriges Modell';

  @override
  String get settingsNextModel => 'Nächstes Modell';

  @override
  String get settingsToggleAutoFollow => 'Auto-Folgen umschalten';

  @override
  String get settingsPreviousSession => 'Vorherige Sitzung';

  @override
  String get settingsNextSession => 'Nächste Sitzung';

  @override
  String get settingsSaveFile => 'Datei speichern';

  @override
  String get settingsTriggerCompletion => 'Vervollständigung auslösen';

  @override
  String get settingsShowSignatureHelp => 'Signaturhilfe anzeigen';

  @override
  String get settingsFind => 'Suchen';

  @override
  String get settingsFindAndReplace => 'Suchen und Ersetzen';

  @override
  String get settingsGoToLine => 'Zur Zeile gehen';

  @override
  String get settingsDocumentSymbols => 'Dokumentsymbole';

  @override
  String get settingsWorkspaceSymbols => 'Arbeitsbereichssymbole';

  @override
  String get settingsGoToDefinition => 'Zur Definition gehen';

  @override
  String get settingsFindReferences => 'Verweise finden';

  @override
  String get settingsGoToImplementation => 'Zur Implementierung gehen';

  @override
  String get settingsShowHoverInfo => 'Hover-Info anzeigen';

  @override
  String get settingsRenameSymbol => 'Symbol umbenennen';

  @override
  String get settingsCodeActions => 'Code-Aktionen';

  @override
  String get settingsFormatDocument => 'Dokument formatieren';

  @override
  String get settingsDefaultsToCtrlEnterAndTriggers =>
      'Standard: Strg + Enter; löst die Senden-Schaltfläche aus, wenn das Chat-Eingabefeld bereit ist.';

  @override
  String get settingsDefaultsToCtrlPForQuickly =>
      'Standard: Strg + P, um das Eingabefeld schnell ein- oder auszuklappen.';

  @override
  String get settingsDefaultsToCtrlLeftAndWraps =>
      'Standard: Strg + Links; wickelt sich bei Bedarf zum letzten Modell.';

  @override
  String get settingsDefaultsToCtrlRightAndWraps =>
      'Standard: Strg + Rechts; wickelt sich bei Bedarf zum ersten Modell.';

  @override
  String get settingsDefaultsToCtrlSForToggling =>
      'Standard: Strg + S zum Umschalten von Auto-Folgen.';

  @override
  String get settingsDefaultsToCtrlUpAndWraps =>
      'Standard: Strg + Hoch; wickelt sich bis zum Ende der Sitzungsliste.';

  @override
  String get settingsDefaultsToCtrlDownAndWraps =>
      'Standard: Strg + Runter; wickelt sich zum Anfang der Sitzungsliste.';

  @override
  String get settingsUndoLastFileMutation => 'Letzte Dateimutation rückgängig';

  @override
  String get settingsDefaultsToCtrlShiftZForUndo =>
      'Standard: Strg + Umschalt + Z. Macht die neueste Dateimutation der aktuellen Sitzung rückgängig.';

  @override
  String get auditDeleteMessage => 'Nachricht löschen';

  @override
  String get auditDeleteThisMessageThisCannotBe =>
      'Diese Nachricht löschen? Dies kann nicht rückgängig gemacht werden.';

  @override
  String get auditCancel => 'Abbrechen';

  @override
  String get settingsManageTheBuiltInAiTools =>
      'Verwalten Sie die integrierten KI-Werkzeuge. Passen Sie für jedes Werkzeug Aktivierungsstatus, Name, Beschreibung, Schema, Priorität usw. an.';

  @override
  String get settingsManageTheLocalFilesAndDatabase =>
      'Verwalten Sie die lokalen Dateien und Datenbanktabellen, die OpenHand auf der Festplatte besitzt. Jede Bereinigung läuft auf Hintergrund-Workern, um die UI nicht zu blockieren.';

  @override
  String get settingsThisWillRestoreAllBuiltIn =>
      'Dies stellt alle integrierten Werkzeugkonfigurationen auf Werkseinstellungen zurück, einschließlich Name, Beschreibung, Schema usw.';

  @override
  String get tlCallUnwrap => 'Umbruch aufheben';

  @override
  String get tlCallWrapLines => 'Zeilen umbrechen';

  @override
  String get tlCallViewCompressedContent => 'Komprimierten Inhalt anzeigen';

  @override
  String get tlCallViewFullContent => 'Vollständigen Inhalt anzeigen';

  @override
  String get tlCallPreparing => 'Wird vorbereitet';

  @override
  String get tlCallPreparingAlt => 'Wird vorbereitet';

  @override
  String get tlCallRunningAlt => 'Läuft';

  @override
  String get tlCallCompleted => 'Abgeschlossen';

  @override
  String get tlCallCompletedAlt => 'Abgeschlossen';

  @override
  String get tlCallTimedOutAlt => 'Zeitüberschreitung';

  @override
  String get tlCallFailedAlt => 'Fehlgeschlagen';

  @override
  String tlCallFailedToOpenFileLocationError(Object error) {
    return 'Dateispeicherort konnte nicht geöffnet werden: $error';
  }

  @override
  String tlCallMemoryitemsLengthMemoriesUpdated(Object memoryItems_length) {
    return '$memoryItems_length Erinnerungen aktualisiert';
  }

  @override
  String tlCallProfileitemsLengthProfileChanges(Object profileItems_length) {
    return '$profileItems_length Profiländerungen';
  }

  @override
  String tlCallSkillitemsLengthSkillsUpdated(Object skillItems_length) {
    return '$skillItems_length Fähigkeiten aktualisiert';
  }

  @override
  String get tlCallAiThinkingStreaming => 'KI denkt (Streaming)';

  @override
  String get tlCallAiThinking => 'KI denkt';

  @override
  String get tlCallAiResponseStreaming => 'KI-Antwort (Streaming)';

  @override
  String get tlCallAiResponse => 'KI-Antwort';

  @override
  String tlCallAndItemsLength3More(Object items_length_3, Object items_length) {
    return ' und $items_length_3 weitere';
  }

  @override
  String tlCallSecondsSAgo(Object seconds) {
    return 'vor ${seconds}s';
  }

  @override
  String tlCallMinutesMAgo(Object minutes) {
    return 'vor $minutes Min';
  }

  @override
  String tlCallHoursHAgo(Object hours) {
    return 'vor $hours Std';
  }

  @override
  String tlCallDaysDAgo(Object days) {
    return 'vor $days Tagen';
  }

  @override
  String sessMetaPlanPlanindex(Object planIndex) {
    return 'Plan #$planIndex';
  }

  @override
  String sessMetaTheCurrentSequentialToolRoundLimit(Object configuredLimit) {
    return 'Das aktuelle Limit für aufeinanderfolgende Werkzeugrunden beträgt $configuredLimit.';
  }

  @override
  String auditInvalidJsonErrorMessage(Object error_message) {
    return 'Ungültiges JSON: $error_message';
  }

  @override
  String auditSaveFailedError(Object error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String auditRecentErrorsSessionRecenterrorsLength(
    Object session_recentErrors_length,
  ) {
    return 'Kürzliche Fehler ($session_recentErrors_length)';
  }

  @override
  String auditMessagesSessionMessagesLength(Object session_messages_length) {
    return 'Nachrichten ($session_messages_length)';
  }

  @override
  String progExpFEAppliedEditsLengthFormattingEdits(Object edits_length) {
    return '$edits_length Formatierungs-Bearbeitungen angewendet.';
  }

  @override
  String progExpFEFormatTheCurrentFileFormatshortcut(Object formatShortcut) {
    return 'Aktuelle Datei formatieren ($formatShortcut)';
  }

  @override
  String progExpFENoCodeactionkindRefactoringIsAvailableAt(
    Object codeActionKind,
  ) {
    return 'Am aktuellen Punkt ist keine „$codeActionKind“-Refaktorisierung verfügbar.';
  }

  @override
  String get progExpFEHideFileBrowser => 'Dateibrowser ausblenden';

  @override
  String get progExpFEShowFileBrowser => 'Dateibrowser anzeigen';

  @override
  String settingsRetentionWindowRetentionDayS(Object retention) {
    return 'Aufbewahrungsfenster: $retention Tag(e)';
  }

  @override
  String settingsRangeMinrMaxrDaysDefault7(Object minR, Object maxR) {
    return 'Bereich $minR–$maxR Tage; Standard 7. Wirkt sich beim nächsten Kaltstart aus.';
  }

  @override
  String settingsConcurrentWorkersConcurrency(Object concurrency) {
    return 'Gleichzeitige Worker: $concurrency';
  }

  @override
  String settingsCapsHowManySessionsCanBe(Object minC, Object maxC) {
    return 'Begrenzt, wie viele Sitzungen pro Tick parallel verteilt werden können ($minC–$maxC). Standard 5.';
  }

  @override
  String settingsSortedLengthBuiltInToolsEnabledcount(
    Object sorted_length,
    Object enabledCount,
  ) {
    return '$sorted_length integrierte Werkzeuge, $enabledCount aktiviert. Name, Beschreibung, Schema, Priorität usw. anpassen.';
  }

  @override
  String settingsAreYouSureYouWantTo(Object config_effectiveName) {
    return 'Möchten Sie „$config_effectiveName“ wirklich löschen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String settingsEnterAValueBetweenMinAnd(Object min, Object max) {
    return 'Wert zwischen $min und $max Sekunden eingeben.';
  }

  @override
  String settingsPleaseEnterAnIntegerBetweenAppsettingssn(
    Object AppSettingsSnapshot_minAiInputCacheUpdateInterval,
    Object AppSettingsSnapshot_maxAiInputCacheUpdateInterval,
  ) {
    return 'Bitte geben Sie eine Ganzzahl zwischen $AppSettingsSnapshot_minAiInputCacheUpdateInterval und $AppSettingsSnapshot_maxAiInputCacheUpdateInterval ein.';
  }

  @override
  String settingsPleaseEnterAnIntegerBetweenAppsettingssn2(
    Object AppSettingsSnapshot_minAiInputCacheBreakpointCount,
    Object AppSettingsSnapshot_maxAiInputCacheBreakpointCount,
  ) {
    return 'Bitte geben Sie eine Ganzzahl zwischen $AppSettingsSnapshot_minAiInputCacheBreakpointCount und $AppSettingsSnapshot_maxAiInputCacheBreakpointCount ein.';
  }

  @override
  String settingsDragTheThumbcountThumbsToPosition(Object thumbCount) {
    return 'Ziehen Sie $thumbCount Punkte, um Verlaufskandidaten festzulegen (0%-100%). Stabile und fortlaufende Endanker belegen das Budget zuerst; der rechte Punkt bleibt am aktuellen Anfrageende.';
  }

  @override
  String get settingsTheDenyCommandRuleHasBeen2 =>
      'Verweigerungs-Befehlsregel aktualisiert.';

  @override
  String get settingsTheAllowCommandRuleHasBeen2 =>
      'Erlaubnis-Befehlsregel aktualisiert.';

  @override
  String settingsDefaultsToDefaultlabelAndSavesThe(Object defaultLabel) {
    return 'Standard: $defaultLabel; speichert die aktuelle Datei.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndOpensThe(Object defaultLabel) {
    return 'Standard: $defaultLabel; öffnet bei Bedarf das Vervollständigungs-Popup.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsMethod(Object defaultLabel) {
    return 'Standard: $defaultLabel; zeigt Methodensignaturen, Parameterdetails und Zusammenfassungsdokumentation für das aktuelle Symbol.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe(Object defaultLabel) {
    return 'Standard: $defaultLabel; schaltet das Suchpanel um.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe2(Object defaultLabel) {
    return 'Standard: $defaultLabel; schaltet das Ersetzen-Panel um.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe3(Object defaultLabel) {
    return 'Standard: $defaultLabel; schaltet das Gehe-zu-Zeile-Panel um.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe4(Object defaultLabel) {
    return 'Standard: $defaultLabel; schaltet die Symbolliste der aktuellen Datei um.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe5(Object defaultLabel) {
    return 'Standard: $defaultLabel; schaltet das Suchpanel für Arbeitsbereichssymbole um.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndJumpsTo(Object defaultLabel) {
    return 'Standard: $defaultLabel; springt zur aktuellen Symboldefinition.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndFindsReferences(Object defaultLabel) {
    return 'Standard: $defaultLabel; findet Verweise für das aktuelle Symbol.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndJumpsTo2(Object defaultLabel) {
    return 'Standard: $defaultLabel; springt zur aktuellen Implementierung.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsType(Object defaultLabel) {
    return 'Standard: $defaultLabel; zeigt Typ- oder Dokumentationsinformationen an der aktuellen Position.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndStartsRename(Object defaultLabel) {
    return 'Standard: $defaultLabel; startet die Umbenennung für das aktuelle Symbol.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsAvailable(Object defaultLabel) {
    return 'Standard: $defaultLabel; zeigt verfügbare Code-Aktionen an.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndFormatsThe(Object defaultLabel) {
    return 'Standard: $defaultLabel; formatiert die aktuelle Programmdatei; Shift+Tab führt zuerst noch ein Outdent aus.';
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
    return '$lspName für die aktuelle Datei aufgelöst.\nProjektsprache: $projLang\nSprache der aktuellen Datei: $fileLang\n$modeLine\n$sdkSourceLine\n$lspSourceLine\nArbeitsbereich: $rootPath\nBefehl: $command';
  }

  @override
  String get settingsReduceMotionLabel => 'Bewegung reduzieren';

  @override
  String get settingsReduceMotionBody =>
      'Wenn aktiviert, werden eigene und in Flutter eingebaute Animationen übersprungen (Dauer auf null). Wirkt zusammen mit der systemweiten Bedienungshilfe „Bewegung reduzieren“.';

  @override
  String get mcpToolSearchReplayLastCancelAction =>
      'Letzten Abbruch wiederholen';

  @override
  String get mcpToolSearchReplayLastCancelToastFired =>
      'Letzte abgebrochene Ladung wiederholt';

  @override
  String get mcpToolSearchReplayLastCancelToastEmpty => 'Nichts zu wiederholen';

  @override
  String get aiThrottleSettingsLabel => 'Drosselparameter';

  @override
  String get aiThrottleSettingsBody =>
      'Vereinheitlichte Streaming-Drosselung: Hauptschalter, Automatik, Zeichen-/Kartenrate, Dauer.';

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
  String get webReverseSetupTargetUrl => 'Ziel-URL *';

  @override
  String get webReverseSetupObjective => 'Ziel *';

  @override
  String get webReverseSetupObjectiveHint =>
      'z. B. Wallpaper-Download-API rückentwickeln, curl-Skript ausgeben';

  @override
  String get webReverseSetupTriggerActions => 'Auslöseraktionen (optional)';

  @override
  String get webReverseSetupTriggerHint =>
      'z. B. einloggen und dann auf „Original herunterladen“ klicken';

  @override
  String get webReverseSetupLoginMode => 'Login-Modus';

  @override
  String get webReverseSetupBrowser => 'Browser (erkannt)';

  @override
  String get webReverseSetupProxy => 'Proxy (optional)';

  @override
  String get webReverseSetupKeywords =>
      'Schlüsselwörter (optional, kommagetrennt)';

  @override
  String get webReverseSetupCreateThread => 'Thread erstellen';

  @override
  String get webReverseSetupHeaderTitle => 'Neue Web-Reverse-Sitzung';

  @override
  String get webReverseSetupHeaderSubtitle =>
      'Nach dem Start wird der Browser rechts neben dem Hauptfenster angedockt';

  @override
  String get webReverseSetupClose => 'Schließen';

  @override
  String get webReverseSetupProfileDir => 'Profilverzeichnis';

  @override
  String get webReverseSetupLockDetected =>
      'Veraltete SingletonLock-/Lockfile erkannt — könnte den nächsten Start blockieren.';

  @override
  String get webReverseSetupWorking => 'Wird verarbeitet…';

  @override
  String webReverseSetupCooldown(int seconds) {
    return 'Abkühlung ${seconds}s';
  }

  @override
  String get webReverseSetupResolveLock => 'Profilkonflikt lösen';

  @override
  String get webReverseSignatureDiffHeaderTitle =>
      'Signaturfeld-Variablenlokalisierer';

  @override
  String get webReverseSignatureDiffHeaderSubtitle =>
      'Identifiziert dynamische (sign / ts / nonce) vs. stabile Felder über mehrere Captures desselben Endpoints';

  @override
  String get webReverseSignatureDiffRefresh => 'Aktualisieren';

  @override
  String get webReverseSignatureDiffSearchHint => 'Endpoint suchen';

  @override
  String get webReverseSignatureDiffNoGroups =>
      'Keine analysierbaren Gruppen (≥2 Samples nötig)';

  @override
  String get webReverseSignatureDiffEmptyHint =>
      'Rufe dieselbe API im Network-Panel mehrfach auf und kehre dann zur Analyse zurück.';

  @override
  String get webReverseSignatureDiffCopyReport => 'Bericht kopieren';

  @override
  String get webReverseSignatureDiffStable => 'Stabil';

  @override
  String get webReverseSignatureDiffDynamic => 'Dynamisch';

  @override
  String get webReverseSignatureDiffIncreasing => 'Aufsteigend';

  @override
  String get webReverseSignatureDiffFixedHash => 'Fixe Länge Hash';

  @override
  String get webReverseSignatureDiffSectionQuery => 'Query-Parameter';

  @override
  String get webReverseSignatureDiffSectionHeaders => 'Request-Header';

  @override
  String get webReverseSignatureDiffSectionBody => 'Request-Body JSON-Felder';

  @override
  String get webReverseSignatureDiffReportTitle => 'Signaturfeld-Analyse';

  @override
  String get webReverseSignatureDiffReportSamples => 'Samples';

  @override
  String get webReverseSignatureDiffReportCopied =>
      'Bericht in die Zwischenablage kopiert';

  @override
  String get webReverseCoverageStartFailed => 'Start fehlgeschlagen';

  @override
  String get webReverseCoverageCollecting => 'Sammlung läuft…';

  @override
  String get webReverseCoverageTakeFailed => 'Sampling fehlgeschlagen';

  @override
  String get webReverseCoverageStopped => 'Gestoppt';

  @override
  String get webReverseCoverageReportCopied => 'Bericht kopiert';

  @override
  String get webReverseCoverageTitle => 'JS-Abdeckung';

  @override
  String get webReverseCoverageSubtitle =>
      'Starten → Seite verwenden → Sample nehmen, um zu sehen, welche Skripte liefen';

  @override
  String get webReverseCoverageRecording => 'AUFNAHME';

  @override
  String get webReverseCoverageStart => 'Starten';

  @override
  String get webReverseCoverageTake => 'Sample';

  @override
  String get webReverseCoverageStop => 'Stopp';

  @override
  String get webReverseCoverageFilterHint => 'Nach URL filtern';

  @override
  String get webReverseCoverageCopyReport => 'Bericht kopieren';

  @override
  String get webReverseCoverageNoData =>
      'Keine Daten. Start → Seite verwenden → Take.';

  @override
  String get webReverseCoverageClose => 'Schließen';

  @override
  String get webReverseCoverageCopyUrl => 'URL kopieren';

  @override
  String get webReverseCoverageCopied => 'Kopiert';

  @override
  String webReverseCoverageSampledCount(int count) {
    return '$count Skripte abgetastet';
  }

  @override
  String get webReverseDeviceEmuTitle => 'Geräteemulation';

  @override
  String get webReverseDeviceEmuPresets => 'Voreinstellungen';

  @override
  String get webReverseDeviceEmuCustom => 'Benutzerdefiniert';

  @override
  String get webReverseDeviceEmuWidth => 'Breite';

  @override
  String get webReverseDeviceEmuHeight => 'Höhe';

  @override
  String get webReverseDeviceEmuMobileMode => 'Mobil (touch + meta viewport)';

  @override
  String get webReverseDeviceEmuUaHint =>
      'Leer lassen, um Standard-UA beizubehalten';

  @override
  String get webReverseDeviceEmuApplyCustom => 'Benutzerdefiniert anwenden';

  @override
  String get webReverseDeviceEmuReset => 'Zurücksetzen';

  @override
  String get webReverseDeviceEmuClose => 'Schließen';

  @override
  String get webReverseDeviceEmuMinSize => 'Mindestgröße 100×100';

  @override
  String get webReverseDeviceEmuResetDone => 'Auf Standard zurückgesetzt';

  @override
  String get webReverseDeviceEmuApplied => 'Angewendet';

  @override
  String get webReverseDeviceEmuClearingOverrides =>
      'Überschreibungen werden gelöscht…';

  @override
  String get webReverseDeviceEmuApplyingCustom =>
      'Benutzerdefinierte Metriken werden angewendet…';

  @override
  String webReverseDeviceEmuApplyingPreset(String label) {
    return '$label wird angewendet…';
  }

  @override
  String webReverseDeviceEmuAppliedPreset(String label) {
    return '$label angewendet';
  }

  @override
  String webReverseDeviceEmuAppliedCustomSize(int w, int h, String dpr) {
    return '$w×$h @ ${dpr}x angewendet';
  }

  @override
  String get webReverseWatchCopiedJson => 'JSON kopiert';

  @override
  String get webReverseWatchTitle => 'Beobachtungsausdrücke';

  @override
  String get webReverseWatchExportJson => 'JSON exportieren';

  @override
  String get webReverseWatchPause => 'Pause';

  @override
  String get webReverseWatchResume => 'Fortsetzen';

  @override
  String get webReverseWatchNoExpressions => 'Keine Ausdrücke';

  @override
  String get webReverseWatchAwaiting => 'Wartet…';

  @override
  String get webReverseWatchDelete => 'Löschen';

  @override
  String get webReverseWatchNameLabel => 'Name (optional)';

  @override
  String get webReverseWatchExpressionLabel => 'JS-Ausdruck';

  @override
  String get webReverseWatchAddWatch => 'Beobachtung hinzufügen';

  @override
  String get webReverseWatchPickWatch => 'Beobachtung links wählen';

  @override
  String get webReverseWatchClose => 'Schließen';

  @override
  String get webReverseWatchInterval => 'Intervall';

  @override
  String get webReverseWatchNewestFirst => 'neueste zuerst';

  @override
  String get webReverseWatchAwaitingFirst => 'Warte auf erste Auswertung…';

  @override
  String webReverseWatchSubtitleHint(int ms, int count) {
    return 'Führt Runtime.evaluate alle ${ms}ms aus, behält letzte $count Stichproben';
  }

  @override
  String webReverseWatchHistory(int count) {
    return 'Verlauf ($count)';
  }

  @override
  String get webReverseAccountSnapTitle => 'Kontoschnappschüsse';

  @override
  String get webReverseAccountSnapSubtitle =>
      'Cookies + localStorage/sessionStorage speichern; Konten per Klick wechseln';

  @override
  String get webReverseAccountSnapNameLabel => 'Name für aktuelles Konto';

  @override
  String get webReverseAccountSnapNameHint => 'z. B. main / test-001';

  @override
  String get webReverseAccountSnapCapture => 'Erfassen';

  @override
  String get webReverseAccountSnapExportAll => 'Alle exportieren';

  @override
  String get webReverseAccountSnapImport => 'Importieren';

  @override
  String get webReverseAccountSnapClose => 'Schließen';

  @override
  String get webReverseAccountSnapEmptyHint =>
      'Noch keine Snapshots. Namen oben eingeben → „Erfassen\" klicken.';

  @override
  String get webReverseAccountSnapApply => 'Anwenden';

  @override
  String get webReverseAccountSnapDelete => 'Löschen';

  @override
  String get webReverseAccountSnapApplyFailedNoCdp =>
      'Anwenden fehlgeschlagen: keine CDP-Sitzung';

  @override
  String get webReverseAccountSnapNotSnapshotJson =>
      'Zwischenablage ist kein Snapshot-JSON';

  @override
  String webReverseAccountSnapSavedSnapshot(String name, int count) {
    return '\"$name\" gespeichert ($count Cookies)';
  }

  @override
  String webReverseAccountSnapAppliedSnapshot(String name) {
    return '\"$name\" angewendet. Seite neu laden, damit JS sie erneut liest.';
  }

  @override
  String webReverseAccountSnapCopiedCount(int count) {
    return '$count Snapshots-JSON in Zwischenablage kopiert';
  }

  @override
  String webReverseAccountSnapImportedCount(int count) {
    return '$count Snapshots importiert';
  }

  @override
  String webReverseAccountSnapSnapshotsCount(int count) {
    return '$count insgesamt';
  }

  @override
  String get webReverseReqBpNewBreakpoint => 'Neuer Breakpoint';

  @override
  String get webReverseReqBpTitle => 'Request-Breakpoints';

  @override
  String get webReverseReqBpSubtitle =>
      'Treffer per URL-/Body-Teilstring protokollieren + optional JS auswerten. Erst „Intercept“ in der Toolbar aktivieren.';

  @override
  String get webReverseReqBpInterceptOff => 'Intercept AUS';

  @override
  String get webReverseReqBpAdd => 'Hinzufügen';

  @override
  String get webReverseReqBpEmptyHint =>
      'Oben rechts auf + tippen, um den ersten Breakpoint anzulegen';

  @override
  String get webReverseReqBpUnnamed => '(unbenannt)';

  @override
  String get webReverseReqBpPickHint =>
      'Links einen Breakpoint zum Bearbeiten wählen';

  @override
  String get webReverseReqBpClear => 'Leeren';

  @override
  String get webReverseReqBpNoHits => 'Noch keine Treffer';

  @override
  String get webReverseReqBpNameField => 'Name';

  @override
  String get webReverseReqBpAnyMethod => 'Beliebig';

  @override
  String get webReverseReqBpUrlContains => 'URL enthält';

  @override
  String get webReverseReqBpBodyContains => 'Body enthält';

  @override
  String get webReverseReqBpEvalOnHit => 'Bei Treffer ausführen (optional)';

  @override
  String get webReverseReqBpEvalHint =>
      'z. B. debugger; oder console.trace(\"hit\", new Error().stack)';

  @override
  String get webReverseReqBpDeleteBreakpoint => 'Breakpoint löschen';

  @override
  String webReverseReqBpHitsCount(int count) {
    return 'Treffer (zuletzt $count)';
  }

  @override
  String get webReverseWsInjectTitle => 'WebSocket-Injektion';

  @override
  String get webReverseWsInjectSubtitle =>
      'Alle Seiten-WebSockets laufen über Proxy → Ziel wählen → beliebigen Textframe senden';

  @override
  String get webReverseWsInjectProxyOn => 'PROXY AKTIV';

  @override
  String get webReverseWsInjectInstallFailed => 'Installation fehlgeschlagen';

  @override
  String get webReverseWsInjectRefresh => 'Aktualisieren';

  @override
  String get webReverseWsInjectNoLive =>
      'Keine aktiven WebSockets.\nSeite neu laden, damit der Proxy neue Verbindungen abfängt.';

  @override
  String get webReverseWsInjectPayloadLabel => 'Zu sendender Textframe / JSON';

  @override
  String get webReverseWsInjectPaste => 'Einfügen';

  @override
  String get webReverseWsInjectPickTarget => 'Zielverbindung wählen';

  @override
  String get webReverseWsInjectTargetLabel => 'Ziel';

  @override
  String get webReverseWsInjectLogEmpty => 'Injektionsprotokoll erscheint hier';

  @override
  String get webReverseWsInjectClose => 'Schließen';

  @override
  String get webReverseWsInjectSend => 'Senden';

  @override
  String get webReverseWsInjectInjected => 'Injiziert';

  @override
  String get webReverseWsInjectInjectFailed => 'Injektion fehlgeschlagen';

  @override
  String webReverseWsInjectLiveCount(int count) {
    return '$count aktive WebSocket(s)';
  }

  @override
  String webReverseWsInjectSentBytes(int count) {
    return '$count Bytes gesendet';
  }

  @override
  String webReverseWsInjectFailedReason(String reason) {
    return 'Fehler: $reason';
  }

  @override
  String get webReversePmTitle => 'postMessage-Trace';

  @override
  String get webReversePmSubtitle =>
      'Hook injizieren → Ringpuffer → alle 800 ms abrufen (inkl. iframe)';

  @override
  String get webReversePmHookInjected => 'postMessage-Hook injiziert';

  @override
  String get webReversePmHookStopped => 'Gestoppt';

  @override
  String get webReversePmStop => 'Stopp';

  @override
  String get webReversePmInject => 'Injizieren';

  @override
  String get webReversePmClear => 'Leeren';

  @override
  String get webReversePmCopyJson => 'JSON kopieren';

  @override
  String get webReversePmFilterHint => 'Filter nach Teilstring';

  @override
  String get webReversePmChipSend => 'Senden';

  @override
  String get webReversePmChipRecv => 'Empfangen';

  @override
  String get webReversePmWaiting => 'Warte auf postMessage…';

  @override
  String get webReversePmClickToCapture =>
      'Auf „Injizieren“ klicken, um Aufzeichnung zu starten';

  @override
  String get webReversePmTagSend => 'SENDEN';

  @override
  String get webReversePmTagRecv => 'EMPF';

  @override
  String get webReversePmClose => 'Schließen';

  @override
  String webReversePmCopiedCount(int count) {
    return '$count Einträge kopiert';
  }

  @override
  String get webReverseThrottleEnableNetwork => 'Network-Domain aktivieren…';

  @override
  String get webReverseThrottleApplyFailed => 'Anwendung fehlgeschlagen';

  @override
  String get webReverseThrottleConditionsApplied =>
      'Netzwerkbedingungen angewendet';

  @override
  String get webReverseThrottleTitle => 'Netzwerk-Throttling';

  @override
  String get webReverseThrottleSubtitle =>
      'Network.emulateNetworkConditions: Presets oder benutzerdefinierte kbps/Latenz';

  @override
  String get webReverseThrottlePresets => 'Presets';

  @override
  String get webReverseThrottleCustom => 'Benutzerdefiniert';

  @override
  String get webReverseThrottleDownKbps => 'Down kbps (0=∞)';

  @override
  String get webReverseThrottleUpKbps => 'Up kbps (0=∞)';

  @override
  String get webReverseThrottleLatencyMs => 'Latenz ms';

  @override
  String get webReverseThrottleOffline => 'Offline';

  @override
  String get webReverseThrottleDisableCache => 'Cache deaktivieren';

  @override
  String get webReverseThrottleApplyCustom => 'Anwenden';

  @override
  String get webReverseThrottleReset => 'Zurücksetzen (kein Throttle)';

  @override
  String get webReverseThrottleNotes => 'Hinweise';

  @override
  String get webReverseThrottleNotesBody =>
      '· Throttle gilt für die gesamte Session des aktuellen Targets; zurücksetzen oder schließen.\n· kbps wird vor dem Senden über *1024/8 in bytes/s umgerechnet; offline ignoriert Durchsatz.\n· Cache-Deaktivierung gilt für Fetch & Disk Cache, nützlich für Cold-Load.';

  @override
  String get webReverseThrottleClose => 'Schließen';

  @override
  String get webReverseThrottleUnknownError => 'unbekannt';

  @override
  String webReverseThrottleStatusFailed(String reason) {
    return 'Fehler: $reason';
  }

  @override
  String webReverseThrottleStatusApplied(String summary) {
    return 'Angewendet: $summary';
  }

  @override
  String get webReverseDomMutTitle => 'DOM-Mutation-Recorder';

  @override
  String get webReverseDomMutSubtitle =>
      'MutationObserver injizieren → Live-Timeline';

  @override
  String get webReverseDomMutRecordingStarted =>
      'DOM-Mutationen werden aufgezeichnet';

  @override
  String webReverseDomMutInstallFailed(String error) {
    return 'Installation fehlgeschlagen: $error';
  }

  @override
  String webReverseDomMutCopiedRecords(int count) {
    return '$count Einträge kopiert';
  }

  @override
  String get webReverseDomMutExportJson => 'JSON exportieren';

  @override
  String get webReverseDomMutRecording => 'Aufzeichnung';

  @override
  String get webReverseDomMutStart => 'Start';

  @override
  String get webReverseDomMutStop => 'Stopp';

  @override
  String get webReverseDomMutClear => 'Leeren';

  @override
  String get webReverseDomMutFilterHint => 'Filter (Teilstring)';

  @override
  String get webReverseDomMutAutoFollow => 'Auto-Folgen';

  @override
  String webReverseDomMutCounter(int count, int total) {
    return '$count / $total';
  }

  @override
  String get webReverseDomMutWaiting => 'Warte auf Mutationen…';

  @override
  String get webReverseDomMutPressStart => 'Start drücken';

  @override
  String get webReverseDomMutClose => 'Schließen';

  @override
  String get webReverseSmTitle => 'SourceMap-Resolver';

  @override
  String get webReverseSmSubtitle =>
      'min file:line:col → original source:line:col';

  @override
  String get webReverseSmInvalidInput => 'ungültige Eingabe';

  @override
  String get webReverseSmFetching => 'Sourcemap wird geladen...';

  @override
  String webReverseSmFetchFailed(String error) {
    return 'Laden fehlgeschlagen: $error';
  }

  @override
  String get webReverseSmBadEvalResult => 'Ungültiges Evaluierungsergebnis';

  @override
  String get webReverseSmNoMapping => 'Kein Mapping-Segment gefunden';

  @override
  String get webReverseSmResolved => 'Aufgelöst';

  @override
  String get webReverseSmCopied => 'Kopiert';

  @override
  String get webReverseSmUrlLabel => 'Minifizierte Datei-URL';

  @override
  String get webReverseSmLineLabel => 'Zeile (1-basiert)';

  @override
  String get webReverseSmColLabel => 'Spalte (0-basiert)';

  @override
  String get webReverseSmResolve => 'Auflösen';

  @override
  String get webReverseSmEmptyHint =>
      'URL und Position eingeben, dann auflösen';

  @override
  String get webReverseSmCopyTooltip => 'Kopieren';

  @override
  String get webReverseSmNameLabel => 'Name';

  @override
  String get webReverseSmClose => 'Schließen';

  @override
  String get webReverseCssCovStarting =>
      'CSS-Domäne aktivieren und Verfolgung starten...';

  @override
  String webReverseCssCovStartFailed(String error) {
    return 'Start fehlgeschlagen: $error';
  }

  @override
  String get webReverseCssCovTrackingActive =>
      'Wird verfolgt — interagiere mit der Seite, dann „Stoppen & Auswerten“ klicken.';

  @override
  String get webReverseCssCovStopping => 'Stoppe und aggregiere...';

  @override
  String webReverseCssCovStopFailed(String error) {
    return 'Stopp fehlgeschlagen: $error';
  }

  @override
  String webReverseCssCovResultsTallied(int sheets, int rules) {
    return '$sheets Stylesheets, insgesamt $rules Regeln.';
  }

  @override
  String get webReverseCssCovJsonCopied => 'JSON kopiert';

  @override
  String get webReverseCssCovTitle => 'CSS-Regel-Abdeckung';

  @override
  String get webReverseCssCovSubtitle =>
      'CSS.startRuleUsageTracking · ungenutzte Regeln finden';

  @override
  String get webReverseCssCovCopyJson => 'JSON kopieren';

  @override
  String get webReverseCssCovTracking => 'Verfolgung läuft';

  @override
  String get webReverseCssCovIdle => 'Leerlauf';

  @override
  String get webReverseCssCovStopAndTally => 'Stoppen & Auswerten';

  @override
  String get webReverseCssCovStartTracking => 'Verfolgung starten';

  @override
  String get webReverseCssCovEmpty =>
      'Noch keine Ergebnisse. Verfolgung starten und Seite verwenden.';

  @override
  String webReverseCssCovRuleStats(
    int used,
    int total,
    String usedKb,
    String totalKb,
  ) {
    return '$used/$total Regeln · $usedKb/$totalKb KB';
  }

  @override
  String get webReverseCssCovClose => 'Schließen';

  @override
  String get webReverseAiCryptoStatusFetchResources =>
      'Frame-Ressourcen werden geladen...';

  @override
  String get webReverseAiCryptoStatusDetecting =>
      'Verdächtige Felder werden erkannt...';

  @override
  String get webReverseAiCryptoStatusDone => 'Fertig';

  @override
  String get webReverseAiCryptoCopied => 'In Zwischenablage kopiert';

  @override
  String get webReverseAiCryptoTitle => 'KI Krypto-Parameter wiederherstellen';

  @override
  String get webReverseAiCryptoSubtitle =>
      'Endpoint gruppieren → Variablen diff → in JS lokalisieren → Prompt kopieren';

  @override
  String get webReverseAiCryptoRefresh => 'Neu gruppieren';

  @override
  String get webReverseAiCryptoEmpty =>
      'Kein analysierbarer Endpoint (≥2 Treffer pro Endpoint nötig)';

  @override
  String get webReverseAiCryptoAnalyze => 'Analysieren';

  @override
  String get webReverseAiCryptoCopyPrompt => 'Prompt kopieren';

  @override
  String get webReverseAiCryptoSuspectsLabel => 'Verdächtige Felder:';

  @override
  String get webReverseAiCryptoPromptHint =>
      'Klicken Sie auf Analysieren, um den Prompt zu erzeugen.';

  @override
  String get webReverseAiCryptoClose => 'Schließen';

  @override
  String webReverseAiCryptoStatusSearchProgress(int done, int total) {
    return 'Suche $done/$total';
  }

  @override
  String webReverseAiCryptoHits(int count) {
    return '$count Treffer';
  }

  @override
  String get webReverseCdpSendFailed => 'Senden fehlgeschlagen';

  @override
  String get webReverseCdpCopied => 'Kopiert';

  @override
  String get webReverseCdpTitle => 'CDP Raw Konsole';

  @override
  String get webReverseCdpMethodLabel => 'method (Domain.command)';

  @override
  String get webReverseCdpUseSession => 'Page-Session verwenden';

  @override
  String get webReverseCdpSend => 'Senden';

  @override
  String get webReverseCdpNoHistory => 'Kein Verlauf';

  @override
  String get webReverseCdpSendHint => 'Befehl senden, um Antwort zu sehen';

  @override
  String get webReverseCdpClose => 'Schließen';

  @override
  String get webReverseCdpCopyResponse => 'Antwort kopieren';

  @override
  String get webReverseCdpParams => 'Parameter';

  @override
  String get webReverseCdpResponse => 'Antwort';

  @override
  String get webReverseCdpError => 'Fehler';

  @override
  String webReverseCdpInvalidJson(String error) {
    return 'Ungültiges JSON: $error';
  }

  @override
  String webReverseCdpSubtitle(int count) {
    return '⌘/Ctrl+Enter senden · Ctrl+↑/↓ Verlauf · $count Einträge';
  }

  @override
  String get webReversePerfTitle => 'Performance Trace';

  @override
  String get webReversePerfSubtitle => 'Tracing → chrome-trace JSON';

  @override
  String get webReversePerfDuration => 'Dauer';

  @override
  String get webReversePerfCategories => 'Trace-Kategorien';

  @override
  String get webReversePerfCopyPath => 'Pfad kopieren';

  @override
  String get webReversePerfStop => 'Stopp';

  @override
  String get webReversePerfStart => 'Start';

  @override
  String get webReversePerfClose => 'Schließen';

  @override
  String get webReversePerfTraceFailed => 'Trace fehlgeschlagen oder leer';

  @override
  String get webReversePerfStopping => 'Wird beendet, finalisiert…';

  @override
  String get webReversePerfTraceSaved => 'Trace gespeichert';

  @override
  String get webReversePerfPathCopied => 'Pfad kopiert';

  @override
  String webReversePerfRecording(int seconds) {
    return 'Aufnahme (${seconds}s übrig)';
  }

  @override
  String webReversePerfSaved(String path, String kb) {
    return 'Gespeichert: $path ($kb KB)';
  }

  @override
  String get webReverseReplayJsonCopied => 'JSON kopiert';

  @override
  String get webReverseReplayTitle => 'Netzwerk-Batch-Replay';

  @override
  String get webReverseReplaySubtitle =>
      'Mehrfachauswahl → seq. Wiederholung → Diff';

  @override
  String get webReverseReplayCopyResultsJson => 'Ergebnisse als JSON kopieren';

  @override
  String get webReverseReplayFilterByUrl => 'Nach URL filtern';

  @override
  String get webReverseReplaySelectAll => 'Alle auswählen';

  @override
  String get webReverseReplayClear => 'Leeren';

  @override
  String get webReverseReplayEmpty => 'Keine HTTP-Anfragen in der Sitzung';

  @override
  String get webReverseReplayRunBatch => 'Batch starten';

  @override
  String get webReverseReplayClose => 'Schließen';

  @override
  String webReverseReplayDone(int ok, int total) {
    return 'Replay fertig: $ok/$total ok';
  }

  @override
  String webReverseReplayProgress(int done, int total) {
    return 'Wiederholt $done / $total';
  }

  @override
  String webReverseReplaySelected(int count, int total) {
    return 'Ausgewählt $count / $total';
  }

  @override
  String get webReverseGeoOverridesApplied => 'Overrides angewendet';

  @override
  String get webReverseGeoEnvOverridesApplied =>
      'Umgebungs-Overrides angewendet';

  @override
  String get webReverseGeoOverridesCleared => 'Overrides aufgehoben';

  @override
  String get webReverseGeoEnvOverridesCleared =>
      'Umgebungs-Overrides aufgehoben';

  @override
  String get webReverseGeoTitle => 'Geo / TZ / Locale Override';

  @override
  String get webReverseGeoCityPresets => 'Stadt-Presets';

  @override
  String get webReverseGeoEnableGeo => 'Geolocation-Override aktivieren';

  @override
  String get webReverseGeoEnableTz => 'Zeitzonen-Override aktivieren';

  @override
  String get webReverseGeoEnableLocale => 'Locale-Override aktivieren';

  @override
  String get webReverseGeoTip =>
      'Tipp: Overrides gelten sofort im aktuellen Target und bleiben nach Reload erhalten. Prüfung via navigator.geolocation, Intl.DateTimeFormat().resolvedOptions().timeZone, navigator.language. Bei zwischengespeicherter Erkennung Hard-Reload nach Override.';

  @override
  String get webReverseGeoClear => 'Löschen';

  @override
  String get webReverseGeoWorking => 'Wird ausgeführt…';

  @override
  String get webReverseGeoApply => 'Overrides anwenden';

  @override
  String get webReverseCollectionExportNothing => 'Nichts zu exportieren';

  @override
  String get webReverseCollectionExportTitle => 'API-Sammlung exportieren';

  @override
  String get webReverseCollectionExportSubtitle =>
      'Postman / Insomnia / Bruno / cURL / HAR — in die Zwischenablage kopieren';

  @override
  String get webReverseCollectionExportName => 'Sammlungsname';

  @override
  String get webReverseCollectionExportUrlFilter => 'URL-Filter';

  @override
  String get webReverseCollectionExportXhrOnly => 'Nur XHR/Fetch';

  @override
  String get webReverseCollectionExportPreview2 => 'Vorschau: erste 2 Einträge';

  @override
  String get webReverseCollectionExportClose => 'Schließen';

  @override
  String get webReverseCollectionExportCopyAction => 'Sammlung kopieren';

  @override
  String get webReverseCollectionExportNoMatch =>
      '// Keine passenden Requests.\n// Filter anpassen oder „Nur XHR/Fetch\" deaktivieren.';

  @override
  String webReverseCollectionExportCopied(int count) {
    return '$count Requests in Zwischenablage kopiert';
  }

  @override
  String webReverseCollectionExportMatchCount(int match, int total) {
    return '$match Treffer · $total insgesamt';
  }

  @override
  String get webReverseJwtTitle => 'JWT Auto-Refresh';

  @override
  String get webReverseJwtSubtitle =>
      'JWTs in Cookies/Storage scannen, Refresh-JS bei nahem Ablauf ausführen';

  @override
  String get webReverseJwtScanNow => 'Jetzt scannen';

  @override
  String get webReverseJwtRefreshNow => 'Jetzt aktualisieren';

  @override
  String get webReverseJwtAuto => 'Auto';

  @override
  String get webReverseJwtIntervalSec => 'Intervall(s)';

  @override
  String get webReverseJwtThresholdSec => 'Schwelle(s)';

  @override
  String get webReverseJwtRefreshExpr => 'Refresh-Ausdruck (async JS)';

  @override
  String get webReverseJwtNoneFound => 'Kein JWT gefunden';

  @override
  String get webReverseJwtRefreshLog => 'Refresh-Log';

  @override
  String get webReverseJwtClose => 'Schließen';

  @override
  String webReverseJwtFoundCount(int count) {
    return 'Gefundene JWTs ($count)';
  }

  @override
  String get webReverseWebauthnTitle => 'WebAuthn-Virtueller Authenticator';

  @override
  String get webReverseWebauthnDisabledBody =>
      'WebAuthn-Schalter oben rechts aktivieren, dann können virtuelle Authenticators erstellt werden, sodass navigator.credentials.create/get ohne Hardware-Key funktionieren.';

  @override
  String get webReverseWebauthnAdd => 'Virtuellen Authenticator hinzufügen';

  @override
  String get webReverseWebauthnAddBtn => 'Hinzufügen';

  @override
  String get webReverseWebauthnNone => 'Noch keine Authenticators';

  @override
  String get webReverseWebauthnClose => 'Schließen';

  @override
  String get webReverseWebauthnRefreshCreds => 'Credentials aktualisieren';

  @override
  String get webReverseWebauthnRemove => 'Entfernen';

  @override
  String get webReverseWebauthnUserVerified => 'Benutzer verifiziert';

  @override
  String webReverseWebauthnAdded(String id) {
    return 'Authenticator $id hinzugefügt';
  }

  @override
  String webReverseWebauthnCreatedCount(int count) {
    return 'Erstellt ($count)';
  }

  @override
  String webReverseWebauthnCredentialsCount(int count) {
    return 'Credentials ($count)';
  }

  @override
  String get webReverseInstallTitle => 'Google Chrome erforderlich';

  @override
  String get webReverseInstallClose => 'Schließen';

  @override
  String get webReverseInstallBody =>
      'Der Web-Reverse-Expert benötigt einen externen Chromium-Browser (Chrome / Edge / Brave / Chromium), gesteuert via CDP. Keiner wurde gefunden.';

  @override
  String get webReverseInstallOpen => 'Im Browser öffnen';

  @override
  String get webReverseInstallHint =>
      'Chrome installieren und erneut versuchen. Falls Edge / Brave / Chromium installiert ist, auf „Installiert, erneut prüfen\" klicken.';

  @override
  String get webReverseInstallInstalled => 'Installiert';

  @override
  String get webReverseProfileEmptyPath =>
      'Profilpfad ist leer; nichts ausgeführt';

  @override
  String get webReverseProfileNoResidual =>
      'Keine verbleibenden Sperren. Falls der Start fehlschlägt, siehe weitere Ursachen in der Diagnose.';

  @override
  String get webReverseProfileResetTitle =>
      'Sperren noch vorhanden — Profil zurücksetzen?';

  @override
  String get webReverseProfileResetConfirm => 'Jetzt zurücksetzen';

  @override
  String get webReverseProfileKept =>
      'Profil beibehalten; Sperren könnten den nächsten Start blockieren.';

  @override
  String webReverseProfileCleanFailed(String error) {
    return 'Bereinigung fehlgeschlagen: $error';
  }

  @override
  String webReverseProfileCleaned(int count) {
    return '$count Sperrdatei(en) entfernt; Profil ist gesund';
  }

  @override
  String webReverseProfileResetBody(String path) {
    return 'SingletonLock-Reste bereinigt, aber Sperren existieren noch.\n\nFortfahren löscht rekursiv:\n$path\n\nCookies / Login Data / Erweiterungen / Verlauf in diesem Profil gehen verloren; ein frisches Profil wird beim nächsten Start erstellt.';
  }

  @override
  String webReverseProfileResetDone(String path) {
    return 'Profil zurückgesetzt: $path (60s Abkühlung)';
  }

  @override
  String webReverseProfileResetFailed(String error) {
    return 'Zurücksetzen fehlgeschlagen: $error';
  }

  @override
  String get webReverseReplNoResult => '(kein Ergebnis)';

  @override
  String get webReverseReplCopied => 'Kopiert';

  @override
  String get webReverseReplTitle => 'Console REPL';

  @override
  String get webReverseReplSubtitle =>
      'Runtime.evaluate · ↑/↓ Verlauf · Ctrl/⌘+Enter ausführen';

  @override
  String get webReverseReplClear => 'Log leeren';

  @override
  String get webReverseReplEmpty =>
      'JS unten eingeben → Ctrl/⌘+Enter ausführen';

  @override
  String get webReverseReplHint =>
      'z.B.: document.title oder await fetch(\"/api\").then(r=>r.json())';

  @override
  String get webReverseReplRun => 'Ausführen';

  @override
  String get webReverseConsoleEvalFailed => 'Auswertung fehlgeschlagen';

  @override
  String get webReverseConsoleEmpty => 'Noch keine Konsolenausgabe.';

  @override
  String get webReverseConsolePausedHint =>
      'Debugger pausiert · Ausdrücke werden im obersten Frame-Scope ausgewertet';

  @override
  String get webReverseConsoleReplHint => 'JS-Ausdruck; ↑↓ Verlauf';

  @override
  String get webReverseConsoleClusterCopied => 'Cluster-JSON kopiert';

  @override
  String get webReverseConsoleClusterTitle => 'Konsolen-Cluster';

  @override
  String get webReverseConsoleClusterRefresh => 'Aktualisieren';

  @override
  String get webReverseConsoleClusterFilterHint => 'Filter';

  @override
  String get webReverseConsoleClusterNoMatch => 'Keine passenden Einträge';

  @override
  String get webReverseConsoleClusterCopyJson => 'JSON kopieren';

  @override
  String webReverseConsoleClusterSubtitle(int entries, int clusters) {
    return 'Dedupliziert nach Level + normalisierter erster Zeile · $entries Einträge / $clusters Cluster';
  }

  @override
  String webReverseConsoleClusterTimes(String first, String last) {
    return 'Erste: $first\nLetzte: $last';
  }

  @override
  String webReverseConsoleClusterMore(int count) {
    return '… und $count weitere';
  }

  @override
  String get webReverseDomSearchTitle => 'DOM-Selektorsuche';

  @override
  String get webReverseDomSearchSearching => 'Suche...';

  @override
  String get webReverseDomSearchNoMatches => 'Keine Treffer';

  @override
  String get webReverseDomSearchHint =>
      'Selektor / Text / XPath eingeben, Enter zum Ausführen';

  @override
  String get webReverseDomSearchRun => 'Ausführen';

  @override
  String get webReverseDomSearchExample =>
      'Bsp.: button[data-action] · #login · //a[contains(@href,\"docs\")]';

  @override
  String get webReverseDomSearchHighlight => 'Auf Seite hervorheben';

  @override
  String webReverseDomSearchFailed(String error) {
    return 'Fehlgeschlagen: $error';
  }

  @override
  String webReverseDomSearchGetFailed(String error) {
    return 'Ergebnisse abrufen fehlgeschlagen: $error';
  }

  @override
  String webReverseDomSearchHitCount(int total, int shown) {
    return '$total Treffer, oben $shown angezeigt';
  }

  @override
  String get webReverseFrameTreeTitle => 'Frame-Baum';

  @override
  String get webReverseFrameTreeSubtitle =>
      'Page.getFrameTree · Haupt + verschachtelte iframes';

  @override
  String get webReverseFrameTreeRefresh => 'Aktualisieren';

  @override
  String get webReverseFrameTreeCopyJson => 'JSON kopieren';

  @override
  String get webReverseFrameTreeCopied => 'Kopiert';

  @override
  String get webReverseFrameTreeEmpty => 'Keine Frames';

  @override
  String webReverseFrameTreeFailed(String error) {
    return 'Fehlgeschlagen: $error';
  }

  @override
  String webReverseFrameTreeCount(int count) {
    return '$count Frames';
  }

  @override
  String get webReverseCpuThrottleOff => 'CPU-Drosselung aus';

  @override
  String get webReverseCpuThrottleResetDone => 'Zurückgesetzt';

  @override
  String get webReverseCpuThrottleTitle => 'CPU-Drosselung';

  @override
  String get webReverseCpuThrottlePresets => 'Voreinstellungen';

  @override
  String get webReverseCpuThrottleNote =>
      'Drosselung bleibt nach dem Schließen aktiv. 1× (off) wählen oder „Zurücksetzen“ klicken.';

  @override
  String get webReverseCpuThrottleReset => 'Zurücksetzen (1×)';

  @override
  String webReverseCpuThrottleApplying(String rate) {
    return 'CPU-Drosselung $rate× wird gesetzt...';
  }

  @override
  String webReverseCpuThrottleFailed(String error) {
    return 'Fehlgeschlagen: $error';
  }

  @override
  String webReverseCpuThrottleCurrent(String rate) {
    return 'CPU gedrosselt $rate×';
  }

  @override
  String webReverseCpuThrottleSliderLabel(String rate) {
    return 'Schieberegler $rate×';
  }

  @override
  String webReverseCpuThrottleApplied(String rate) {
    return 'Drosselung $rate× angewendet';
  }

  @override
  String get webReverseHeapTaking =>
      'Heap-Snapshot wird erfasst (kann einige Sekunden dauern)...';

  @override
  String get webReverseHeapFailed => 'Snapshot fehlgeschlagen oder leer';

  @override
  String get webReverseHeapSavedToast => 'Snapshot gespeichert';

  @override
  String get webReverseHeapPathCopied => 'Pfad kopiert';

  @override
  String get webReverseHeapSubtitle =>
      'HeapProfiler.takeHeapSnapshot → .heapsnapshot (DevTools Memory ladbar)';

  @override
  String get webReverseHeapEmptyHint =>
      'Klicken Sie unten, um den V8-Heap-Snapshot der aktuellen Seite zu erfassen.\nGroße Seiten können 50MB+ erzeugen.';

  @override
  String get webReverseHeapCopyPath => 'Pfad kopieren';

  @override
  String get webReverseHeapTake => 'Snapshot erstellen';

  @override
  String webReverseHeapSaved(String path, String mb) {
    return 'Gespeichert: $path ($mb MB)';
  }

  @override
  String get webReverseRealtimeDirSent => 'Gesendet';

  @override
  String get webReverseRealtimeDirRecv => 'Empfangen';

  @override
  String get webReverseRealtimeDirError => 'Fehler';

  @override
  String get webReverseRealtimePayloadCopied => 'Payload kopiert';

  @override
  String get webReverseRealtimeTitle => 'Echtzeit';

  @override
  String get webReverseRealtimeEmpty =>
      'Noch kein WebSocket / EventSource auf der Seite.\nNach einer Aktion wird hier in Echtzeit aktualisiert.';

  @override
  String get webReverseRealtimePickPrompt =>
      'Wählen Sie links eine Verbindung, um Frames anzuzeigen.';

  @override
  String get webReverseRealtimeFilterHint => 'Payload filtern (Teilstring)';

  @override
  String get webReverseRealtimeAutoFollow => 'Automatisch folgen';

  @override
  String get webReverseRealtimeNoMatching => 'Keine passenden Frames.';

  @override
  String webReverseRealtimeFrameCount(int count) {
    return '$count Frames';
  }

  @override
  String get webReverseMarkupTitle => 'Screenshot-Annotation';

  @override
  String get webReverseMarkupSaveWithout => 'Ohne Annotation speichern';

  @override
  String get webReverseMarkupExporting => 'Exportiere…';

  @override
  String get webReverseMarkupDone => 'Fertig';

  @override
  String get webReverseMarkupUndo => 'Rückgängig';

  @override
  String get webReverseMarkupClear => 'Leeren';

  @override
  String get webReverseMarkupAddTextTitle => 'Textbeschriftung hinzufügen';

  @override
  String get webReverseMarkupLabelHint => 'Beschriftung eingeben';

  @override
  String get webReverseMarkupAdd => 'Hinzufügen';

  @override
  String get webReverseElementsLoadFailed =>
      'Laden fehlgeschlagen: Browser nicht aktiv oder CDP nicht verfügbar';

  @override
  String get webReverseElementsSelectorFailed =>
      'Selector konnte nicht erstellt werden';

  @override
  String get webReverseElementsSelectorCopied => 'Selector kopiert';

  @override
  String get webReverseElementsXPathFailed =>
      'XPath konnte nicht erstellt werden';

  @override
  String get webReverseElementsXPathCopied => 'XPath kopiert';

  @override
  String get webReverseElementsReloadDom => 'DOM-Wurzel neu laden';

  @override
  String get webReverseElementsCopySelector => 'Selector kopieren';

  @override
  String get webReverseElementsCopyXPath => 'XPath kopieren';

  @override
  String get webReverseElementsScrollIntoView => 'In Sicht scrollen';

  @override
  String get webReverseElementsPickElement => 'Element aus dem Baum auswählen';

  @override
  String get webReverseElementsNoAttrs => 'Keine Attribute';

  @override
  String get webReverseElementsNoComputed => 'Kein berechneter Stil';

  @override
  String get webReverseElementsNoListeners => 'Keine Event-Listener';

  @override
  String webReverseElementsAttrsTab(int count) {
    return 'Attr. ($count)';
  }

  @override
  String webReverseElementsComputedTab(int count) {
    return 'Berechnet ($count)';
  }

  @override
  String webReverseElementsListenersTab(int count) {
    return 'Listener ($count)';
  }

  @override
  String get webReverseCryptoSecEncode => 'Codieren';

  @override
  String get webReverseCryptoSecHash => 'Hash';

  @override
  String get webReverseCryptoSecTime => 'Zeit';

  @override
  String get webReverseCryptoClear => 'Leeren';

  @override
  String get webReverseCryptoInputHint => 'Hier einfügen…';

  @override
  String get webReverseCryptoInputLabel => 'Eingabe';

  @override
  String get webReverseCryptoCopy => 'Kopieren';

  @override
  String get webReverseCryptoUseAsInput => 'Als Eingabe verwenden';

  @override
  String get webReverseCryptoLengthLabel => 'Länge';

  @override
  String get webReverseCryptoTsToIso => 'Zeitstempel → ISO';

  @override
  String get webReverseCryptoIsoToTs => 'ISO → Zeitstempel';

  @override
  String get webReverseCryptoNow => 'Jetzt';

  @override
  String get webReverseCryptoUuidHint =>
      'Zufällige UUID v4 (zum Kopieren tippen)';

  @override
  String get webReverseCryptoRegenerate => 'Neu erzeugen';

  @override
  String webReverseCryptoCopied(String label) {
    return '$label kopiert';
  }

  @override
  String webReverseCryptoLengthValue(int chars, int bytes) {
    return 'Zeichen $chars / Bytes $bytes';
  }

  @override
  String get webReverseHooksDefaultCode =>
      'Wird vor jedem Laden des Dokuments ausgeführt; patcht window/fetch usw.';

  @override
  String get webReverseHooksSavedToast => 'Gespeichert und neu geladen';

  @override
  String get webReverseHooksDeleteTitle => 'Hook löschen?';

  @override
  String get webReverseHooksDeleteContent =>
      'Wird sofort entladen und kann nicht rückgängig gemacht werden.';

  @override
  String get webReverseHooksDelete => 'Löschen';

  @override
  String get webReverseHooksDiscardTitle =>
      'Nicht gespeicherte Änderungen verwerfen?';

  @override
  String get webReverseHooksKeepEditing => 'Weiter bearbeiten';

  @override
  String get webReverseHooksDiscardConfirm => 'Verwerfen';

  @override
  String get webReverseHooksLibrary => 'Hook-Bibliothek';

  @override
  String get webReverseHooksNew => 'Neuer Hook';

  @override
  String get webReverseHooksEmpty =>
      'Noch keine Hooks.\nTippe + zum Erstellen.';

  @override
  String get webReverseHooksPickPrompt =>
      'Wähle links einen Hook oder erstelle einen neuen.';

  @override
  String get webReverseHooksNameLabel => 'Name';

  @override
  String get webReverseHooksSave => 'Speichern (⌘S)';

  @override
  String get webReverseHooksSaved => 'Gespeichert';

  @override
  String get webReverseHooksInfo =>
      'Speichern lädt sofort neu. Läuft vor jedem Dokumentladen; bleibt nach Tab-Wechsel/Reload aktiv.';

  @override
  String webReverseHooksNewName(String time) {
    return 'Hook $time';
  }

  @override
  String get webReverseSnippetsDefaultCode =>
      'Schreibe hier JS. Läuft im Seitenkontext.';

  @override
  String get webReverseSnippetsNoResult => '(kein Ergebnis)';

  @override
  String get webReverseSnippetsDeleteTitle => 'Snippet löschen?';

  @override
  String get webReverseSnippetsDeleteContent =>
      'Kann nicht rückgängig gemacht werden.';

  @override
  String get webReverseSnippetsDelete => 'Löschen';

  @override
  String get webReverseSnippetsTitle => 'Snippet-Pad';

  @override
  String get webReverseSnippetsNew => 'Neues Snippet';

  @override
  String get webReverseSnippetsEmpty =>
      'Noch keine Snippets.\nTippe + zum Erstellen.';

  @override
  String get webReverseSnippetsPickPrompt =>
      'Wähle links ein Snippet oder erstelle eines.';

  @override
  String get webReverseSnippetsRun => 'Ausführen (⌘R)';

  @override
  String get webReverseSnippetsSaveDirty => 'Speichern *';

  @override
  String webReverseSnippetsNewName(String time) {
    return 'Snippet $time';
  }

  @override
  String get servicesTitle => 'Dienste';

  @override
  String get servicesSubtitle =>
      'Nutzen Sie von OpenHand entwickelte Fachdienste für eine stabile, kontrollierte und auditierbare Ausführung.';

  @override
  String get servicesProprietaryBadge => 'Von OpenHand entwickelt';

  @override
  String get servicesAiInfrastructureExposureScanTitle =>
      'Scan exponierter KI-Infrastruktur';

  @override
  String get servicesAiInfrastructureExposureScanDescription =>
      'Erkennt exponierte KI-Dienste im autorisierten Bereich, identifiziert offengelegte Zugangsdaten und riskante Konfigurationen und sichert auditierbare Belege für die Behebung.';

  @override
  String get hookEventSessionStart => 'Sitzungsstart';

  @override
  String get hookEventUserPromptSubmit => 'Prompt gesendet';

  @override
  String get hookEventPreToolUse => 'Vor Werkzeugnutzung';

  @override
  String get hookEventPostToolUse => 'Nach Werkzeugnutzung';

  @override
  String get hookEventSubagentStart => 'Subagent gestartet';

  @override
  String get hookEventSubagentStop => 'Subagent gestoppt';

  @override
  String get hookEventStop => 'Stopp';

  @override
  String get hookEventPreCompact => 'Vor Komprimierung';

  @override
  String get hookEventSessionEnd => 'Sitzungsende';

  @override
  String get hookEventErrorOccurred => 'Fehler aufgetreten';

  @override
  String get builtinToolLoadStrategyEagerShort => 'Sofort';

  @override
  String get builtinToolLoadStrategyLazy => 'Lazy';

  @override
  String get builtinToolLoadStrategyDeferred => 'Verzögert';

  @override
  String get builtinToolLoadStrategyEagerFull => 'Sofort laden';

  @override
  String get builtinToolCustomBadge => 'Benutzerdefiniert';

  @override
  String get builtinToolForceBadge => 'Erzwingen';

  @override
  String get builtinToolMoveUp => 'Nach oben';

  @override
  String get builtinToolMoveDown => 'Nach unten';

  @override
  String builtinToolEditorTitle(String kind) {
    return 'Werkzeug bearbeiten — $kind';
  }

  @override
  String get builtinToolEnableTitle => 'Werkzeug aktivieren';

  @override
  String get builtinToolEnableBody =>
      'Deaktiviert erscheint dieses Werkzeug nicht im Werkzeugkatalog des Modells.';

  @override
  String get builtinToolDisplayNameLabel => 'Anzeigename (optional)';

  @override
  String get builtinToolDisplayNameHelper =>
      'Überschreibt den Standardnamen. Leer lassen für den integrierten Standard.';

  @override
  String get builtinToolSummaryLabel => 'Kurzbeschreibung (optional)';

  @override
  String get builtinToolSummaryHelper =>
      'Wird in der Werkzeugliste zur schnellen Orientierung angezeigt.';

  @override
  String get builtinToolPromptOverrideLabel => 'Prompt-Ergänzung (optional)';

  @override
  String get builtinToolPromptOverrideHelper =>
      'Wird an die Werkzeugbeschreibung angehängt und steuert die Nutzung durch das Modell.';

  @override
  String get builtinToolSchemaOverrideLabel =>
      'Schema-Override (JSON, optional)';

  @override
  String get builtinToolSchemaOverrideHelper =>
      'Vollständiges JSON-Schema für Eingabeparameter. Leer lassen für Standard.';

  @override
  String get builtinToolPriorityLabel => 'Priorität (0–9999)';

  @override
  String get builtinToolPriorityHelper => 'Kleiner = höhere Priorität';

  @override
  String get builtinToolLoadStrategyLabel => 'Ladestrategie';

  @override
  String get builtinToolForceLoadTitle => 'Laden erzwingen';

  @override
  String get builtinToolForceLoadBody =>
      'Aktiviert wird dieses Schema direkt gesendet, auch wenn Lazy Loading Auto oder Ein ist.';

  @override
  String get builtinToolMaxOutputLabel => 'Max. Ausgabe (Zeichen)';

  @override
  String get builtinToolGlobalDefaultHint => 'Globaler Standard';

  @override
  String get builtinToolTagsLabel => 'Tags (kommagetrennt)';

  @override
  String get builtinToolTagsHelper => 'z. B. io, file, dangerous';

  @override
  String get builtinToolRequireConfirmationTitle => 'Bestätigung erforderlich';

  @override
  String get builtinToolRequireConfirmationBody =>
      'Fragt vor der Ausführung nach Bestätigung. „Standard“ nutzt das Werkzeugverhalten.';

  @override
  String get builtinToolConfirmationDefault => 'Standard';

  @override
  String get builtinToolConfirmationYes => 'Ja';

  @override
  String get builtinToolConfirmationNo => 'Nein';

  @override
  String get memoryTitleField => 'Titel (optional)';

  @override
  String get memoryTitleHint =>
      'Fassen Sie diese Erinnerung in einem Satz zusammen; leer lassen für eine Inhaltsvorschau';

  @override
  String get commonRetry => 'Erneut versuchen';

  @override
  String get commonOk => 'OK';

  @override
  String get commonExport => 'Exportieren';

  @override
  String get appUpdateDialogTitle => 'Nach Updates suchen';

  @override
  String get appUpdateChecking => 'Suche nach Updates...';

  @override
  String appUpdateCurrentVersion(Object version) {
    return 'Aktuell: $version';
  }

  @override
  String appUpdateNewVersion(Object version) {
    return 'Neue Version: v$version';
  }

  @override
  String appUpdatePublished(Object date) {
    return 'Veröffentlicht: $date';
  }

  @override
  String appUpdateFileSize(Object size) {
    return 'Größe: $size';
  }

  @override
  String get appUpdateAlreadyLatestTitle => 'Sie sind auf dem neuesten Stand';

  @override
  String appUpdateAlreadyLatestBody(Object version) {
    return 'OpenHand $version ist die neueste Version.';
  }

  @override
  String get appUpdateDownloadComplete => 'Download abgeschlossen';

  @override
  String get appUpdateDownloading => 'Wird heruntergeladen...';

  @override
  String get appUpdateCheckFailed => 'Updateprüfung fehlgeschlagen';

  @override
  String get appUpdateLater => 'Später';

  @override
  String get appUpdateDownload => 'Herunterladen';

  @override
  String get exportRangeInvalid =>
      'Gültigen Bereich eingeben (1 ≤ Start ≤ Ende)';

  @override
  String get exportRangeStart => 'Start';

  @override
  String get exportRangeEnd => 'Ende';

  @override
  String get exportSessionSettingsTitle => 'Sitzungseinstellungen exportieren';

  @override
  String exportTotalMessages(Object count) {
    return 'Verfügbare Nachrichten: $count';
  }

  @override
  String get exportRolesSection => 'Rollen';

  @override
  String get exportAllRoles => 'Alle Rollen';

  @override
  String get exportMessageKindsSection => 'Nachrichtentypen';

  @override
  String get exportAllKinds => 'Alle Typen';

  @override
  String get exportMessageRangeSection => 'Nachrichtenbereich';

  @override
  String get exportOnlyRange =>
      'Nur einen Bereich exportieren (1-basiert, inklusiv)';

  @override
  String get exportOtherOptions => 'Weitere Optionen';

  @override
  String get exportIncludeDeleted => 'Gelöschte Nachrichten einschließen';

  @override
  String get exportPickOneRole => 'Mindestens eine Rolle auswählen.';

  @override
  String get exportPickOneMessageKind =>
      'Mindestens einen Nachrichtentyp auswählen.';

  @override
  String get exportRoleSystem => 'System';

  @override
  String get exportRoleUser => 'Benutzer';

  @override
  String get exportRoleAssistant => 'Assistent';

  @override
  String get exportRoleTool => 'Werkzeug';

  @override
  String get exportKindUser => 'Benutzernachricht';

  @override
  String get exportKindAssistant => 'Assistentenantwort';

  @override
  String get exportKindReasoning => 'Denkprozess';

  @override
  String get exportKindToolCall => 'Werkzeugaufruf';

  @override
  String get exportKindTool => 'Werkzeugergebnis';

  @override
  String get exportKindCompressionPoint => 'Komprimierungspunkt';

  @override
  String get exportKindMcp => 'MCP-Ereignis';

  @override
  String get exportKindSkill => 'Skill-Ereignis';

  @override
  String get exportKindHook => 'Hook-Ereignis';

  @override
  String get exportKindSelfLearning => 'Selbstlernen';

  @override
  String get exportKindFileMutationSummary => 'Dateiänderungsübersicht';

  @override
  String get exportKindStatus => 'Statusmeldung';

  @override
  String get exportPhaseLogRangeSection => 'Phasenprotokollbereich';

  @override
  String exportTotalPhaseLogs(Object count) {
    return 'Verfügbare Phasenprotokolle: $count';
  }

  @override
  String get modelSearchHint => 'Modelle suchen…';

  @override
  String modelSearchResultCount(Object filtered, Object total) {
    return '$filtered / $total Modelle';
  }

  @override
  String get modelSearchNoAvailableModels => 'Keine Modelle verfügbar';

  @override
  String get modelSearchNoMatchingModels => 'Keine passenden Modelle';

  @override
  String get modelSearchRecent => 'Zuletzt verwendet';

  @override
  String get nativeAudioLoadFailed =>
      'Audio konnte nicht geladen werden. Öffnen Sie es mit dem Systemplayer.';

  @override
  String get nativeAudioPlaybackFailed =>
      'Wiedergabe fehlgeschlagen. Versuchen Sie es erneut oder öffnen Sie den Systemplayer.';

  @override
  String get nativeAudioBack15Seconds => '15 s zurück';

  @override
  String get nativeAudioPause => 'Pause';

  @override
  String get nativeAudioPlay => 'Wiedergabe';

  @override
  String get nativeAudioForward15Seconds => '15 s vor';

  @override
  String get nativeAudioMute => 'Stummschalten';

  @override
  String get nativeAudioUnmute => 'Stummschaltung aufheben';

  @override
  String get nativeAudioSystemPlayer => 'Systemplayer';

  @override
  String get nativeAudioSequencePlayback => 'Sequenzwiedergabe';

  @override
  String get nativeAudioRepeatOne => 'Einzeltitel wiederholen';

  @override
  String get nativeAudioShufflePlayback => 'Zufallswiedergabe';

  @override
  String nativeAudioEffectTooltip(Object effect) {
    return 'Effekt: $effect';
  }

  @override
  String get nativeAudioEffectStandard => 'Standard';

  @override
  String get nativeAudioEffectSpatial => '3D';

  @override
  String get nativeAudioEffectVocal => 'Stimme';

  @override
  String get nativeAudioEffectWarm => 'Warm';

  @override
  String get hooksTitle => 'Hooks';

  @override
  String get hooksSubtitle =>
      'Konfigurieren Sie Skripte für jede Lebenszyklusphase des KI-Agenten. Hooks werden nacheinander ausgeführt, wenn das passende Ereignis ausgelöst wird.';

  @override
  String get hooksNew => 'Neuer Hook';

  @override
  String get hooksDeleteTitle => 'Hook löschen';

  @override
  String hooksDeleteMessage(Object label) {
    return '„$label“ löschen? Diese Aktion kann nicht rückgängig gemacht werden.';
  }

  @override
  String get hooksEmptyTitle => 'Noch keine Hooks konfiguriert';

  @override
  String get hooksEmptyBody =>
      'Klicken Sie oben auf „Neuer Hook“, um zu beginnen.';

  @override
  String get hooksTimeoutTooltip => 'Timeout';

  @override
  String hooksInlineScriptDescription(Object firstLine) {
    return 'Inline: $firstLine';
  }

  @override
  String get hooksNoScriptConfigured => 'Kein Skript konfiguriert';

  @override
  String get hooksEditTitle => 'Hook bearbeiten';

  @override
  String get hooksLabelField => 'Bezeichnung';

  @override
  String get hooksLabelHint => 'z. B. Logging';

  @override
  String get hooksTriggerEvent => 'Auslösendes Ereignis';

  @override
  String get hooksScriptSource => 'Skriptquelle';

  @override
  String get hooksScriptSourceFile => 'Datei';

  @override
  String get hooksScriptSourceInline => 'Inline';

  @override
  String get hooksScriptFilePath => 'Skriptdateipfad';

  @override
  String get hooksScriptFileHint => 'Wählen Sie eine .sh / .ps1 / .bat-Datei';

  @override
  String get hooksBrowse => 'Durchsuchen';

  @override
  String get hooksScriptContextFileHelp =>
      'Der Kontext-JSON wird auf zwei sichere Arten übergeben (beide funktionieren mit jq):\n① Temporäre Datei: jq -r .session_id \"\$OPENHAND_HOOK_CONTEXT_FILE\"\n② Rohes stdin: jq -r .session_id\nFelder: session_id, session_file_path, environment usw.';

  @override
  String get hooksInlineWindowsHint => 'PowerShell- / BAT-Skript eingeben';

  @override
  String get hooksInlineShellHint =>
      'Shell-Skript eingeben (#!/bin/bash nicht erforderlich)';

  @override
  String get hooksScriptContextInlineHelp =>
      'Der Kontext-JSON wird auf zwei sichere Arten übergeben (beide funktionieren mit jq):\n① Temporäre Datei: SID=\$(jq -r .session_id \"\$OPENHAND_HOOK_CONTEXT_FILE\")\n② Rohes stdin: SID=\$(jq -r .session_id)\nFelder: session_id, session_file_path, environment, statistics usw.';

  @override
  String get hooksTimeoutSeconds => 'Timeout (Sekunden)';

  @override
  String get hooksEnabled => 'Aktiviert';

  @override
  String get hooksValidationLabelRequired =>
      'Geben Sie eine Hook-Bezeichnung ein.';

  @override
  String get hooksValidationScriptFileRequired =>
      'Wählen Sie eine Skriptdatei aus.';

  @override
  String get hooksValidationInlineScriptRequired =>
      'Geben Sie den Inline-Skriptinhalt ein.';

  @override
  String get hooksFileTypeScripts => 'Skripte';

  @override
  String get hooksFileTypeShellScripts => 'Shell-Skripte';

  @override
  String get hooksFileTypeAllFiles => 'Alle Dateien';

  @override
  String get commonConfirm => 'Bestätigen';

  @override
  String get choiceInputCustomOptionLabel => 'Benutzerdefinierte Eingabe';

  @override
  String get choiceInputCustomInputHint => 'Antwort hier eingeben…';

  @override
  String get choiceInputCustomOptionDescription =>
      'Diese Option wählen, um eine eigene Antwort einzugeben';

  @override
  String get mediaPreviewImageCopied => 'Bild in die Zwischenablage kopiert.';

  @override
  String get mediaPreviewImageFileOrPathCopied =>
      'Bilddatei oder Pfad in die Zwischenablage kopiert.';

  @override
  String get mediaPreviewMediaFileCopied =>
      'Mediendatei in die Zwischenablage kopiert.';

  @override
  String get mediaPreviewDirectCopyUnavailablePathCopied =>
      'Direktes Kopieren der Mediendatei ist auf dieser Plattform nicht verfügbar. Dateipfad kopiert.';

  @override
  String get mediaPreviewMediaUrlCopied => 'Medien-URL kopiert.';

  @override
  String get mediaPreviewDirectCopyUnavailableTempPathCopied =>
      'Direktes Kopieren der Mediendatei ist auf dieser Plattform nicht verfügbar. Temporären Dateipfad kopiert.';

  @override
  String get mediaPreviewDataCopyFailedUrlCopied =>
      'Mediendaten konnten nicht kopiert werden. Quell-URL kopiert.';

  @override
  String mediaPreviewCopyFailed(Object error) {
    return 'Kopieren fehlgeschlagen: $error';
  }

  @override
  String get mediaPreviewNoSource => 'Medienquelle ist nicht verfügbar.';

  @override
  String get knowledgeVectorDistributionTitle => 'Vektorverteilung';

  @override
  String get knowledgeVectorDistributionLoading =>
      'Vektoren werden abgetastet und projiziert.';

  @override
  String get knowledgeVectorDistributionEmpty =>
      'Die aktuelle Collection enthält keine anzeigbaren Vektoren.';

  @override
  String get knowledgeVectorProjectionSection => 'Projektion';

  @override
  String get knowledgeVectorAlgorithm => 'Algorithmus';

  @override
  String get knowledgeVectorOriginalDimensions => 'Ursprüngliche Dimensionen';

  @override
  String get knowledgeVectorVisiblePoints => 'Sichtbare Punkte';

  @override
  String get knowledgeVectorSampled => 'Abgetastet';

  @override
  String get knowledgeVectorDurationMs => 'Dauer (ms)';

  @override
  String get knowledgeVectorResample => 'Neu abtasten';

  @override
  String get qdrantStatusRefreshIncomplete =>
      'Die Qdrant-Statusaktualisierung lieferte unvollständige Daten.';

  @override
  String get qdrantStatusRawVectorEmpty => 'Gib zuerst einen Rohvektor ein.';

  @override
  String qdrantStatusRawVectorInvalid(Object value) {
    return 'Ungültige Vektorzahl: $value';
  }

  @override
  String qdrantStatusRawVectorDimensionMismatch(int actual, int expected) {
    return 'Der Rohvektor hat $actual Dimensionen; die aktuelle Einstellung erfordert $expected.';
  }

  @override
  String get qdrantStatusPointIdsEmpty => 'Gib zuerst Punkt-/Chunk-IDs ein.';

  @override
  String get qdrantStatusPayloadIndexesSubmitted =>
      'Erstellung der Standard-Payload-Indizes wurde gestartet.';

  @override
  String get qdrantStatusDangerousOpsDisabled =>
      'Aktiviere zuerst gefährliche Admin-Operationen in den Knowledge-Base-Einstellungen.';

  @override
  String get qdrantStatusDeletePointIdsEmpty =>
      'Gib zuerst die zu löschenden Punkt-IDs ein.';

  @override
  String get qdrantStatusDeletePointsTitle => 'Qdrant-Punkte löschen?';

  @override
  String qdrantStatusDeletePointsMessage(int count) {
    return 'Löscht $count Punkte aus der aktuellen Collection. Diese Aktion kann nicht rückgängig gemacht werden.';
  }

  @override
  String get qdrantStatusDeletePointsConfirm => 'Punkte löschen';

  @override
  String get qdrantStatusPointsDeleted => 'Punkte gelöscht.';

  @override
  String get qdrantStatusDeleteCollectionTitle => 'Qdrant-Collection löschen?';

  @override
  String qdrantStatusDeleteCollectionMessage(Object collection) {
    return 'Löscht die Collection „$collection“ und alle darin enthaltenen Punkte. Diese Aktion kann nicht rückgängig gemacht werden.';
  }

  @override
  String get qdrantStatusDeleteCollectionConfirm => 'Collection löschen';

  @override
  String get qdrantStatusCollectionDeleted => 'Collection gelöscht.';

  @override
  String get qdrantStatusDiagnosticsCopied => 'Diagnose kopiert.';

  @override
  String get qdrantStatusTitle => 'Qdrant-Betrieb';

  @override
  String get qdrantStatusTabOverview => 'Übersicht';

  @override
  String get qdrantStatusTabCollections => 'Sammlungen';

  @override
  String get qdrantStatusTabPoints => 'Punkte';

  @override
  String get qdrantStatusTabDiagnostics => 'Diagnose';

  @override
  String get qdrantStatusRefresh => 'Aktualisieren';

  @override
  String get qdrantStatusCopyDiagnostics => 'Diagnose kopieren';

  @override
  String get qdrantStatusHeaderTitle => 'Status der lokalen Vektordatenbank';

  @override
  String get qdrantStatusMetricCollections => 'Sammlungen';

  @override
  String get qdrantStatusMetricPoints => 'Punkte';

  @override
  String get qdrantStatusMetricIndexedVectors => 'Indexierte Vektoren';

  @override
  String get qdrantStatusMetricChunks => 'Chunks';

  @override
  String get qdrantStatusMetricPendingJobs => 'Ausstehende Jobs';

  @override
  String get qdrantStatusMetricWalCapacity => 'WAL-Kapazität';

  @override
  String get qdrantStatusSmoothTrend => 'Geglätteter Trend';

  @override
  String get qdrantStatusNoCollections =>
      'Keine Collection gefunden oder Qdrant ist nicht verfügbar.';

  @override
  String get qdrantStatusPointsSectionTitle => 'Punkte / Suche / Scrollen';

  @override
  String get qdrantStatusPointIdsLabel => 'Punkt-/Chunk-IDs';

  @override
  String get qdrantStatusSourceFilterLabel => 'Quell-ID-Filter';

  @override
  String get qdrantStatusTagFilterLabel => 'Tag-Filter';

  @override
  String get qdrantStatusLimitLabel => 'Grenze';

  @override
  String get qdrantStatusRawVectorLabel =>
      'Rohvektor (Komma oder Leerzeichen, Dimensionen müssen passen)';

  @override
  String get qdrantStatusQueryIds => 'IDs abfragen';

  @override
  String get qdrantStatusScrollFilter => 'Scrollen / Filtern';

  @override
  String get qdrantStatusRawVectorSearch => 'Rohvektorsuche';

  @override
  String get qdrantStatusRebuildPayloadIndexes =>
      'Payload-Indizes neu aufbauen';

  @override
  String get qdrantStatusDeletePoints => 'Punkte löschen';

  @override
  String get qdrantStatusOperationResult => 'Operationsergebnis';

  @override
  String get qdrantStatusRawDiagnosticsJson => 'Rohes Diagnose-JSON';

  @override
  String get qdrantStatusNoDiagnostics => 'Noch keine Diagnose.';

  @override
  String get qdrantStatusLatestOperationResult => 'Letztes Operationsergebnis';

  @override
  String get qdrantStatusOperationLog => 'Operationsprotokoll';

  @override
  String get qdrantStatusNoOperations => 'Noch keine Operationen.';

  @override
  String get qdrantStatusCollectingSamples =>
      'Sammle Samples für die Trendansicht.';

  @override
  String get qdrantStatusTrendPoints => 'Punkte';

  @override
  String get qdrantStatusTrendChunks => 'Chunks';

  @override
  String get qdrantStatusTrendPendingFailed => 'ausstehend/fehlgeschlagen';

  @override
  String qdrantStatusTrendSampleCount(int count) {
    return '$count Pkt.';
  }

  @override
  String get qdrantSectionOverview => 'Übersicht';

  @override
  String get qdrantSectionDockerContainer => 'Docker / Container';

  @override
  String get qdrantSectionApiMetrics => 'Qdrant-API-Metriken';

  @override
  String get qdrantSectionCollectionConfig => 'Collection-Konfiguration';

  @override
  String get qdrantSectionStorageOptimizer => 'Speicher / Optimierer';

  @override
  String get qdrantSectionTelemetry => 'Telemetrie';

  @override
  String get qdrantSectionOpenHandKnowledge => 'OpenHand Knowledge Base';

  @override
  String get qdrantMetricServiceStatus => 'Dienststatus';

  @override
  String get qdrantMetricRestEndpoint => 'REST-Endpunkt';

  @override
  String get qdrantMetricGrpcEndpoint => 'gRPC-Endpunkt';

  @override
  String get qdrantMetricQdrantVersion => 'Qdrant-Version';

  @override
  String get qdrantMetricCurrentCollection => 'Aktuelle Collection';

  @override
  String get qdrantMetricCollectionStatus => 'Collection-Status';

  @override
  String get qdrantMetricOptimizerStatus => 'Optimiererstatus';

  @override
  String get qdrantMetricLastHealthCheck => 'Letzter Health-Check';

  @override
  String get qdrantMetricDockerDaemon => 'Docker-Daemon';

  @override
  String get qdrantMetricContainerCpu => 'Container-CPU';

  @override
  String get qdrantMetricContainerMemory => 'Container-Speicher';

  @override
  String get qdrantMetricNetworkIo => 'Netzwerk-I/O';

  @override
  String get qdrantMetricBlockIo => 'Block-I/O';

  @override
  String get qdrantMetricRestartCount => 'Neustarts';

  @override
  String get qdrantMetricLatestLogSummary => 'Letzte Log-Zusammenfassung';

  @override
  String get qdrantMetricCollectionsTotal => 'Collections gesamt';

  @override
  String get qdrantMetricPointsTotal => 'Punkte gesamt';

  @override
  String get qdrantMetricVectorsTotal => 'Vektoren gesamt';

  @override
  String get qdrantMetricIndexedVectorsTotal => 'Indexierte Vektoren gesamt';

  @override
  String get qdrantMetricSegmentsTotal => 'Segmente';

  @override
  String get qdrantMetricPayloadSchemaFields => 'Payload-Schema-Felder';

  @override
  String get qdrantMetricPayloadSchemaNames => 'Payload-Schema-Namen';

  @override
  String get qdrantMetricVectorSize => 'Vektordimension';

  @override
  String get qdrantMetricDistance => 'Distanz';

  @override
  String get qdrantMetricSingleNodeMode => 'Einzelknotenmodus';

  @override
  String get qdrantMetricPayloadIndexStatus => 'Payload-Indexstatus';

  @override
  String get qdrantMetricClusterStatus => 'Clusterstatus';

  @override
  String get qdrantMetricHnswM => 'HNSW M';

  @override
  String get qdrantMetricHnswEfConstruct => 'HNSW ef_construct';

  @override
  String get qdrantMetricHnswFullScanThreshold => 'HNSW-Full-Scan-Schwelle';

  @override
  String get qdrantMetricHnswMaxIndexingThreads => 'Max. HNSW-Index-Threads';

  @override
  String get qdrantMetricOnDiskPayload => 'Payload auf Datenträger';

  @override
  String get qdrantMetricShardNumber => 'Shard-Anzahl';

  @override
  String get qdrantMetricReplicationFactor => 'Replikationsfaktor';

  @override
  String get qdrantMetricWriteConsistencyFactor => 'Schreibkonsistenzfaktor';

  @override
  String get qdrantMetricReadFanOutFactor => 'Lese-Fan-out-Faktor';

  @override
  String get qdrantMetricOptimizerDeletedThreshold =>
      'Optimierer-Löschschwelle';

  @override
  String get qdrantMetricOptimizerVacuumMinVectorNumber =>
      'Vacuum-Minimum-Vektoren';

  @override
  String get qdrantMetricOptimizerDefaultSegmentNumber =>
      'Standard-Segmentanzahl';

  @override
  String get qdrantMetricOptimizerMaxSegmentSize => 'Max. Segmentgröße';

  @override
  String get qdrantMetricOptimizerIndexingThreshold => 'Indexierungsschwelle';

  @override
  String get qdrantMetricOptimizerFlushIntervalSeconds =>
      'Flush-Intervall Sekunden';

  @override
  String get qdrantMetricWalCapacityMb => 'WAL-Kapazität MB';

  @override
  String get qdrantMetricWalSegmentsAhead => 'WAL-Segmente voraus';

  @override
  String get qdrantMetricQuantization => 'Quantisierung';

  @override
  String get qdrantMetricStrictMode => 'Strikter Modus';

  @override
  String get qdrantMetricTelemetryStatus => 'Telemetriestatus';

  @override
  String get qdrantMetricAppVersion => 'App-Version';

  @override
  String get qdrantMetricAppName => 'App-Name';

  @override
  String get qdrantMetricTelemetryCollections => 'Collection-Telemetrie';

  @override
  String get qdrantMetricTelemetryRequests => 'Request-Telemetrie';

  @override
  String get qdrantMetricSourceCount => 'Quellen';

  @override
  String get qdrantMetricChunkCount => 'Chunks';

  @override
  String get qdrantMetricPendingEmbeddingJobs => 'Ausstehende Embedding-Jobs';

  @override
  String get qdrantMetricFailedEmbeddingJobs =>
      'Fehlgeschlagene Embedding-Jobs';

  @override
  String get qdrantMetricEmbeddingModel => 'Aktuelles Embedding-Modell';

  @override
  String get qdrantMetricEmbeddingDimensions => 'Aktuelle Dimensionen';

  @override
  String get qdrantMetricRetrievalTopN => 'Retrieval topN';

  @override
  String get qdrantMetricRetrievalTopK => 'Finales topK';

  @override
  String get qdrantMetricMinSimilarity => 'Minimale Ähnlichkeit';

  @override
  String get qdrantMetricPromptChunkBudget => 'Prompt-Chunk-Budget';

  @override
  String get qdrantMetricPromptTokenBudget => 'Prompt-Token-Budget';

  @override
  String get qdrantValueYes => 'Ja';

  @override
  String get qdrantValueNo => 'Nein';

  @override
  String get qdrantValueHealthy => 'Gesund';

  @override
  String get qdrantValueUnknown => 'Unbekannt';

  @override
  String get qdrantValueLoading => 'Wird geladen';

  @override
  String get qdrantValueAvailable => 'Verfügbar';

  @override
  String get qdrantValueUnavailable => 'Nicht verfügbar';

  @override
  String get qdrantValuePluginServiceScan => 'Vom Plugin-Dienst gescannt';

  @override
  String get qdrantValuePluginRuntimeMetric =>
      'Vom Plugin-Runtime bereitgestellt';

  @override
  String get qdrantValuePluginDetailsLogs => 'In Plugin-Details verfügbar';

  @override
  String get qdrantValueLocalSingleNodeOrUnavailable =>
      'Lokaler Einzelknoten / nicht verfügbar';

  @override
  String get qdrantValueClusterInfoAvailable => 'Clusterinformationen erhalten';

  @override
  String get qdrantValuePayloadSchemaConfigured =>
      'Payload-Schema konfiguriert';

  @override
  String get qdrantValuePayloadSchemaMissing => 'Kein Payload-Schema gefunden';
}
