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
  String get skills => 'Compétences';

  @override
  String get memory => 'Mémoire';

  @override
  String get mcp => 'MCP';

  @override
  String get settings => 'Paramètres';

  @override
  String get threads => 'Fils';

  @override
  String get threadsLoadMore => 'Charger plus de fils';

  @override
  String get composerHint =>
      'Demandez n\'importe quoi à OpenHand, utilisez / pour les actions et @ pour le contexte';

  @override
  String get composerSend => 'Envoyer';

  @override
  String get chatSending => 'Envoi';

  @override
  String get chatRequestFailed =>
      'Échec de la requête au modèle. Vérifiez la configuration du modèle, la connexion réseau ou le type de protocole.';

  @override
  String get placeholderComingSoon =>
      'Des modules supplémentaires seront ajoutés ici progressivement.';

  @override
  String get settingsTitle => 'Centre des paramètres';

  @override
  String get settingsSubtitle =>
      'Gérez ici le thème, la langue et les informations de l\'application.';

  @override
  String get settingsFilePathLabel => 'Fichier de paramètres';

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
  String get themePaletteSectionTitle => 'Palette de thème';

  @override
  String get themePaletteSectionBody =>
      'Choisissez un préréglage de couleur global. OpenHand en dérivera les surfaces et accents Material 3 Expressive.';

  @override
  String get themePresetDarkNightPurple => 'Violet nuit profonde';

  @override
  String get themePresetDeepSeaBlue => 'Bleu abysse';

  @override
  String get themePresetMistGray => 'Gris brume';

  @override
  String get themePresetObsidianBlack => 'Noir obsidienne';

  @override
  String get themePresetPolarWhite => 'Blanc polaire';

  @override
  String get themePresetFrostMorningBlue => 'Bleu matin givré';

  @override
  String get themePresetDuskMountainGreen => 'Vert montagne crépusculaire';

  @override
  String get themePresetNebulaPurple => 'Violet nébuleuse';

  @override
  String get themePresetEmberOrange => 'Orange braise';

  @override
  String get themePresetTundraGreen => 'Vert toundra';

  @override
  String get themePresetMoonShadowSilver => 'Argent ombre lunaire';

  @override
  String get themePresetAmberGold => 'Or ambré';

  @override
  String get themePresetRainyCyan => 'Cyan pluvieux';

  @override
  String get themePresetGraphiteGray => 'Gris graphite';

  @override
  String get themePresetGlacierBlue => 'Bleu glacier';

  @override
  String get themePresetBlazeRed => 'Rouge brasier';

  @override
  String get themePresetNightfallBlue => 'Bleu tombée de la nuit';

  @override
  String get themePresetColdMoonWhite => 'Blanc lune froide';

  @override
  String get themePresetPineInk => 'Encre de pin';

  @override
  String get themePresetSkyCyan => 'Cyan ciel';

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
  String get aboutPackage => 'Paquet';

  @override
  String get aboutPlatforms => 'Plateformes';

  @override
  String get aboutPlatformsValue => 'macOS 15+ / Windows 10+';

  @override
  String get aboutBuild => 'Numéro de build';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get commonEdit => 'Modifier';

  @override
  String get exportProgressCancelling => 'Annulation…';

  @override
  String get readerFileTypeText => 'Texte brut';

  @override
  String get readerFileTypeCode => 'Code';

  @override
  String knowledgeReaderNoModelForType(Object type) {
    return 'Aucun modèle Reader ne peut lire $type.';
  }

  @override
  String get permissionLabel => 'Accès complet';

  @override
  String get settingsCategoryGeneral => 'Général';

  @override
  String get settingsCategoryAi => 'IA';

  @override
  String get settingsCategorySkills => 'Compétences';

  @override
  String get settingsCategoryMemory => 'Mémoire';

  @override
  String get mcpSectionTitle => 'Services MCP';

  @override
  String get mcpSectionBody =>
      'Gérer le commutateur global MCP et le chemin du fichier de configuration des services. La création, la mise à jour, la suppression et l’activation des services sont synchronisées avec le fichier JSON MCP.';

  @override
  String get mcpEnabledLabel => 'Activer les services MCP';

  @override
  String get mcpEnabledBody =>
      'Lorsque désactivé, les configurations de serveur enregistrées sont conservées mais les fonctionnalités MCP restent désactivées à l’exécution.';

  @override
  String get mcpFilePathLabel => 'Fichier de configuration MCP';

  @override
  String get mcpOpenDirectory => 'Ouvrir le dossier';

  @override
  String get mcpStdioCacheResetAction => 'Réinitialiser le cache stdio';

  @override
  String get mcpStdioCacheResetConfirmTitle =>
      'Réinitialiser le cache stdio isolé ?';

  @override
  String get mcpStdioCacheResetConfirmBody =>
      'Cela supprimera les caches npm/uv/pip sous ~/.openhand/mcp/package-cache. Le prochain lancement d’un MCP stdio retréchargera ses dépendances. Votre ~/.npm global n’est pas affecté.';

  @override
  String get mcpStdioCacheResetConfirm => 'Réinitialiser';

  @override
  String get mcpStdioCacheResetCancel => 'Annuler';

  @override
  String get mcpStdioCacheResetDone => 'Cache isolé vidé.';

  @override
  String get mcpStdioCacheResetFailed =>
      'Échec de la réinitialisation. Supprimez ~/.openhand/mcp/package-cache manuellement.';

  @override
  String get pluginServiceTitle => 'Plugins';

  @override
  String get pluginServiceSubtitle =>
      'Gérez l’installation, les mises à jour et la suppression des plugins facultatifs. Les plugins ajoutent des capacités d’exécution à OpenHand.';

  @override
  String get pluginServiceRescan => 'Réanalyser';

  @override
  String get pluginServiceScanning =>
      'Analyse de l’environnement local des plugins…';

  @override
  String get pluginServiceScanFailed => 'Échec de l’analyse des plugins';

  @override
  String get pluginServiceActionInstall => 'Installer';

  @override
  String get pluginServiceActionUpdate => 'Mettre à jour';

  @override
  String get pluginServiceActionUninstall => 'Désinstaller';

  @override
  String get pluginServiceActionEnable => 'Activer';

  @override
  String get pluginServiceActionDisable => 'Désactiver';

  @override
  String get pluginServiceStatusInstalled => 'Installé';

  @override
  String get pluginServiceStatusNotInstalled => 'Non installé';

  @override
  String get pluginServiceStatusInstalling => 'Installation…';

  @override
  String get pluginServiceStatusUpdating => 'Mise à jour…';

  @override
  String get pluginServiceStatusUninstalling => 'Désinstallation…';

  @override
  String get pluginServiceStatusError => 'Erreur';

  @override
  String get pluginServiceCheckUpdates => 'Vérifier les mises à jour';

  @override
  String get pluginServiceMcpService => 'Service MCP';

  @override
  String pluginServiceInstallDependencyRequired(Object dependency) {
    return '$dependency doit être installé d’abord';
  }

  @override
  String pluginServiceInstallConfirmTitle(Object plugin) {
    return 'Installer $plugin ?';
  }

  @override
  String pluginServiceInstallConfirmMessage(Object plugin) {
    return '$plugin va être installé. Des dépendances peuvent être téléchargées.';
  }

  @override
  String pluginServiceInstallSuccess(Object plugin) {
    return '$plugin installé';
  }

  @override
  String pluginServiceInstallFailure(Object plugin) {
    return 'Échec de l’installation de $plugin';
  }

  @override
  String pluginServiceUpdateConfirmTitle(Object plugin) {
    return 'Mettre à jour $plugin ?';
  }

  @override
  String pluginServiceUpdateConfirmMessage(
    Object plugin,
    Object currentVersion,
    Object latestVersion,
  ) {
    return 'Mettre à jour $plugin de $currentVersion vers $latestVersion.';
  }

  @override
  String pluginServiceUpdateSuccess(Object plugin) {
    return '$plugin mis à jour';
  }

  @override
  String pluginServiceUpdateFailure(Object plugin) {
    return 'Échec de la mise à jour de $plugin';
  }

  @override
  String get pluginServiceCheckUpdateFailed =>
      'Échec de la vérification des mises à jour';

  @override
  String pluginServiceNewVersionAvailable(Object version) {
    return 'Nouvelle version disponible : $version';
  }

  @override
  String get pluginServiceNoUpdatesAvailable => 'Aucune mise à jour disponible';

  @override
  String pluginServiceUninstallBlocked(Object dependent, Object plugin) {
    return '$dependent dépend de $plugin. Désinstallez-le d’abord.';
  }

  @override
  String pluginServiceUninstallConfirmTitle(Object plugin) {
    return 'Désinstaller $plugin ?';
  }

  @override
  String pluginServiceUninstallConfirmMessage(Object plugin) {
    return '$plugin va être supprimé. Cette action est irréversible.';
  }

  @override
  String pluginServiceUninstallSuccess(Object plugin) {
    return '$plugin désinstallé';
  }

  @override
  String pluginServiceUninstallFailure(Object plugin) {
    return 'Échec de la désinstallation de $plugin';
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
    return 'Journaux : $count lignes';
  }

  @override
  String get pluginServiceWaitingForOutput => 'En attente de sortie…';

  @override
  String get pluginServiceExecuting => 'Exécution…';

  @override
  String get pluginServiceCompleted => 'Terminé';

  @override
  String get pluginServiceVersion => 'Version';

  @override
  String get pluginServiceUpdateAvailable => 'Mise à jour disponible';

  @override
  String get pluginServiceDependsOn => 'Dépend de';

  @override
  String get pluginServiceRequiredBy => 'Requis par';

  @override
  String get pluginServiceNone => 'Aucun';

  @override
  String pluginServiceDetailTitle(Object plugin) {
    return 'Détails de $plugin';
  }

  @override
  String get pluginServiceDetailBasicInfo => 'Infos de base';

  @override
  String get pluginServiceDetailName => 'Nom';

  @override
  String get pluginServiceDetailDescription => 'Description';

  @override
  String get pluginServiceDetailStatus => 'État';

  @override
  String get pluginServiceDetailEnvironment => 'Environnement';

  @override
  String get pluginServiceDetailFileSystem => 'Système de fichiers';

  @override
  String get pluginServiceDetailDependencies => 'Dépendances';

  @override
  String get pluginServiceThreadTemplates => 'Modèles de thread';

  @override
  String get pluginServiceTemplates => 'Modèles';

  @override
  String get pluginServiceMcpPackage => 'Paquet MCP';

  @override
  String get pluginServiceMcpBrowserDescription =>
      'Service MCP pour l’automatisation du navigateur';

  @override
  String get pluginServiceDetailProcessors => 'Processeurs';

  @override
  String get pluginServiceDetailInstallPath => 'Chemin d’installation';

  @override
  String get pluginServiceDetailInstallationTarget => 'Cible d’installation';

  @override
  String get pluginServiceDetailInstallMethod => 'Méthode d’installation';

  @override
  String get pluginServiceDetailTargetOs => 'Système cible';

  @override
  String get pluginServiceDetailSupportedPlatforms =>
      'Plateformes prises en charge';

  @override
  String get pluginServiceDetailPackageName => 'Nom du paquet';

  @override
  String get pluginServiceDetailBinaryName => 'Nom de commande';

  @override
  String get pluginServiceDetailRepository => 'Dépôt';

  @override
  String get pluginServiceDetailDocumentation => 'Documentation officielle';

  @override
  String get pluginServiceDetailInstallCommand => 'Commande d’installation';

  @override
  String get pluginServiceDetailUpgradeCommand => 'Commande de mise à niveau';

  @override
  String get pluginServiceDetailUninstallCommand =>
      'Commande de désinstallation';

  @override
  String get pluginServiceDetailExecutablePath => 'Entrée exécutable';

  @override
  String get pluginServiceDetailCacheDirectory => 'Dossier de cache';

  @override
  String get pluginServiceDetailNpmGlobalRoot => 'Racine globale npm';

  @override
  String get pluginServiceDetailCurrentVersion => 'Version';

  @override
  String get pluginServiceDetailLatestVersion => 'Dernière';

  @override
  String get pluginServiceDetailBoundPython => 'Python lié';

  @override
  String get pluginServiceDetailDesktopAppDetected =>
      'Application de bureau détectée';

  @override
  String get pluginServiceDetailDaemonRunning => 'Daemon actif';

  @override
  String get pluginServiceDetailCliAvailable => 'CLI disponible';

  @override
  String get pluginServiceDetailDockerContext => 'Contexte Docker';

  @override
  String get pluginServiceDetailServerVersion => 'Version serveur';

  @override
  String get pluginServiceDetailDockerOs => 'OS Docker';

  @override
  String get pluginServiceDetailDockerRootDir => 'Racine Docker';

  @override
  String get pluginServiceDetailDaemonName => 'Nom du daemon';

  @override
  String get pluginServiceDetailOsType => 'Type d’OS';

  @override
  String get pluginServiceDetailArchitecture => 'Architecture';

  @override
  String get pluginServiceDetailComposeVersion => 'Version Compose';

  @override
  String get pluginServiceDetailDockerDaemonRunning => 'Daemon Docker actif';

  @override
  String get pluginServiceDetailOpenHandManaged => 'Géré par OpenHand';

  @override
  String get pluginServiceDetailContainerId => 'ID du conteneur';

  @override
  String get pluginServiceDetailContainerName => 'Nom du conteneur';

  @override
  String get pluginServiceDetailContainerStatus => 'État du conteneur';

  @override
  String get pluginServiceDetailRunning => 'En cours';

  @override
  String get pluginServiceDetailStartedAt => 'Démarré à';

  @override
  String get pluginServiceDetailFinishedAt => 'Terminé à';

  @override
  String get pluginServiceDetailRestartCount => 'Redémarrages';

  @override
  String get pluginServiceDetailExitCode => 'Code de sortie';

  @override
  String get pluginServiceDetailImage => 'Image';

  @override
  String get pluginServiceDetailImageId => 'ID de l’image';

  @override
  String get pluginServiceDetailPorts => 'Ports';

  @override
  String get pluginServiceDetailRestartPolicy => 'Politique de redémarrage';

  @override
  String get pluginServiceDetailRestEndpoint => 'Endpoint REST';

  @override
  String get pluginServiceDetailGrpcEndpoint => 'Endpoint gRPC';

  @override
  String get pluginServiceDetailDataDirectory => 'Dossier de données';

  @override
  String get pluginServiceDetailHealthResponse => 'Réponse de santé';

  @override
  String get pluginServiceDetailHealthTitle => 'Titre de santé';

  @override
  String get pluginServiceDetailCollectionCount => 'Nombre de collections';

  @override
  String get pluginServiceDetailRuntimeCapabilities => 'Capacités d’exécution';

  @override
  String get pluginServiceDetailApplicationPath => 'Dossier de l’application';

  @override
  String get pluginServiceDetailReleaseChannel => 'Canal de publication';

  @override
  String get pluginServiceDetailVersionSource => 'Source de version';

  @override
  String get pluginServiceDetailVersionApi => 'API de versions';

  @override
  String get pluginServiceDetailBrowserKind => 'Type de navigateur';

  @override
  String get pluginServiceDetailCdpTransport => 'Transport CDP';

  @override
  String get pluginServiceDetailCdpEndpoint => 'Point de terminaison CDP';

  @override
  String get pluginServiceDetailProfileStrategy => 'Stratégie de profil';

  @override
  String get pluginServiceDetailCaptureScope => 'Périmètre de capture';

  @override
  String get pluginServiceDetailCredentialPolicy =>
      'Protection des identifiants';

  @override
  String get pluginServiceDetailSessionCleanup => 'Nettoyage de session';

  @override
  String get pluginServiceDetailUpdatePolicy => 'Stratégie de mise à jour';

  @override
  String get pluginServiceDetailUninstallPolicy =>
      'Stratégie de désinstallation';

  @override
  String get pluginServiceDetailOfficialSite => 'Site officiel';

  @override
  String pluginServiceMcpInstalledVersion(Object version) {
    return 'Installé v$version';
  }

  @override
  String get pluginServiceMcpOperationTimeout =>
      '[timeout] L’opération a expiré ; processus terminé';

  @override
  String pluginServiceMcpOperationCompleted(Object action, Object exitCode) {
    return '✓ $action terminé (exit code: $exitCode)';
  }

  @override
  String pluginServiceMcpOperationFailed(Object action, Object exitCode) {
    return '✗ Échec de $action (exit code: $exitCode)';
  }

  @override
  String pluginServiceMcpOperationError(Object error) {
    return '✗ Erreur : $error';
  }

  @override
  String get pluginServiceMcpVerificationFailed =>
      'La vérification de l’état MCP après l’opération a échoué';

  @override
  String get pluginServiceDescriptionNodejs =>
      'Runtime JavaScript pour scripts JS/TS et chaînes d’outils';

  @override
  String get pluginServiceDescriptionPlaywright =>
      'Framework de tests d’automatisation navigateur pour Chromium, Firefox et WebKit';

  @override
  String get pluginServiceDescriptionHermesAgent =>
      'Runtime Hermes Agent pour l’orchestration d’agents, l’auto-apprentissage et l’affinage des compétences';

  @override
  String get pluginServiceDescriptionPython =>
      'Runtime Python pour scripts, bibliothèques et extensions';

  @override
  String get pluginServiceDescriptionPip =>
      'Gestionnaire de paquets Python pour installer, mettre à niveau et gérer les bibliothèques';

  @override
  String get pluginServiceDescriptionJava =>
      'Runtime JDK pour les outils d’analyse statique Android comme apktool et jadx';

  @override
  String get pluginServiceDescriptionFrida =>
      'Chaîne d’instrumentation dynamique et Hook pour la validation Android à l’exécution';

  @override
  String get pluginServiceDescriptionMitmproxy =>
      'Outil de proxy et capture HTTP(S) pour l’analyse de trafic Web et Android';

  @override
  String get pluginServiceDescriptionApktool =>
      'Outil de dépaquetage APK et d’analyse smali';

  @override
  String get pluginServiceDescriptionJadx => 'Décompilateur Java DEX / APK';

  @override
  String get pluginServiceDescriptionRadare2 =>
      'Outil d’analyse statique binaire et de rétro-ingénierie ELF / native so';

  @override
  String get pluginServiceDescriptionBlutter =>
      'Outil de récupération Flutter Dart AOT pour l’analyse de libapp.so';

  @override
  String get pluginServiceDescriptionDoldrums =>
      'Outil auxiliaire d’analyse Flutter snapshot / ELF';

  @override
  String get pluginServiceDescriptionAnythingAnalyzer =>
      'Outil d’analyse de protocoles et MCP Server pour capture, analyse et intégration Agent';

  @override
  String get pluginServiceDescriptionDocker =>
      'Runtime de conteneurs pour le service local de base vectorielle Qdrant';

  @override
  String get pluginServiceDescriptionQdrant =>
      'Base vectorielle locale pour l’indexation et la recherche d’embeddings de la base de connaissances';

  @override
  String get pluginServiceDescriptionPostgresql =>
      '关系型数据库服务，供 AI 暴露面扫描保存任务与审计数据';

  @override
  String get pluginServiceDescriptionRedis => '内存数据存储服务，供 AI 暴露面扫描执行缓存与任务队列';

  @override
  String get pluginServiceDescriptionDingtalkWorkspaceCli =>
      'DingTalk Workspace CLI pour les workflows d’agents IA dans DingTalk';

  @override
  String get pluginServiceDescriptionGoogleChrome =>
      'Runtime Chrome local pour la capture native CDP des pages et du réseau des forums';

  @override
  String get pluginServiceDetailExternalService => '外部服务';

  @override
  String get pluginServiceDetailServiceRunning => '服务运行中';

  @override
  String get pluginServiceDetailEndpoint => '服务端点';

  @override
  String get pluginServiceTemplateWebReverseExpert => 'Expert Web Reverse';

  @override
  String get pluginServiceTemplateAndroidReverseExpert =>
      'Expert Android Reverse';

  @override
  String get pluginServiceTemplateHermesTalker => 'Hermes Talker';

  @override
  String get mcpStdioMirrorModeLabel => 'Mode du miroir registre';

  @override
  String get mcpStdioMirrorModeBody =>
      'Au démarrage à froid d’un MCP stdio, injecter les miroirs chinois (npmmirror / Tsinghua PyPI) ? auto = selon la langue. Forcer activé / désactivé = ignorer le locale. OPENHAND_MCP_MIRROR=on/off remplace à chaud.';

  @override
  String get mcpStdioMirrorModeAuto => 'Selon la langue';

  @override
  String get mcpStdioMirrorModeForceOn => 'Forcer activé';

  @override
  String get mcpStdioMirrorModeForceOff => 'Forcer désactivé';

  @override
  String get mcpStdioMirrorModeStatusInjected =>
      'Actif : injection de npmmirror / Tsinghua PyPI';

  @override
  String get mcpStdioMirrorModeStatusBypassed =>
      'Actif : registre officiel, sans miroir';

  @override
  String mcpStdioMirrorModeStatusReason(Object reason) {
    return 'Source : $reason';
  }

  @override
  String get mcpStdioMirrorModeReasonEnv => 'Variable OPENHAND_MCP_MIRROR';

  @override
  String get mcpStdioMirrorModeReasonSetting => 'Forcé par les préférences';

  @override
  String mcpStdioMirrorModeReasonLocale(Object locale) {
    return 'Langue système ($locale)';
  }

  @override
  String get mcpStdioMirrorModeReconnectAction =>
      'Reconnecter les serveurs activés avec le nouveau réglage';

  @override
  String get mcpStdioMirrorModeReconnectDone =>
      'Reconnexion déclenchée. Le prochain appel relancera le processus avec le nouveau miroir.';

  @override
  String mcpStdioDialogLogsTitle(Object name) {
    return 'Logs $name';
  }

  @override
  String mcpStdioDialogRuntimeDetailsTitle(Object name) {
    return 'Détails d’exécution $name';
  }

  @override
  String mcpStdioDialogRunningPid(Object pid) {
    return 'En cours · PID $pid';
  }

  @override
  String get mcpStdioDialogStopped => 'Arrêté';

  @override
  String get mcpStdioDialogAutoScroll => 'Défilement auto';

  @override
  String get mcpStdioDialogCopyLogs => 'Copier les logs';

  @override
  String get mcpStdioDialogClearLogs => 'Effacer les logs';

  @override
  String get mcpStdioDialogCopiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get mcpStdioDialogNoLogOutput => 'Aucune sortie de log';

  @override
  String mcpStdioDialogLineCount(int count) {
    return '$count lignes';
  }

  @override
  String mcpStdioDialogUptime(Object uptime) {
    return 'Actif depuis $uptime';
  }

  @override
  String get mcpStdioDialogRefresh => 'Actualiser';

  @override
  String get settingsScraplingRuntimeActionInstall => 'Installer';

  @override
  String get settingsScraplingRuntimeActionUninstall => 'Désinstaller';

  @override
  String settingsScraplingRuntimeCommand(Object action) {
    return '$action le runtime Scrapling';
  }

  @override
  String get settingsScraplingRuntimeInstallTitle =>
      'Installer le runtime Scrapling';

  @override
  String get settingsScraplingRuntimeUninstallTitle =>
      'Désinstaller le runtime Scrapling';

  @override
  String get settingsScraplingRuntimeInstalling => 'Installation…';

  @override
  String get settingsScraplingRuntimeUninstalling => 'Désinstallation…';

  @override
  String get settingsScraplingRuntimeInstalled => 'Installé';

  @override
  String get settingsScraplingRuntimeUninstalled => 'Désinstallé';

  @override
  String get settingsScraplingRuntimeFailed => 'Échec';

  @override
  String get settingsScraplingRuntimeCertificateDiagnosis =>
      'Diagnostic : Python / pip dans l’environnement actuel ne peut pas valider la chaîne de certificats PyPI. Vérifiez les certificats CA du système, les certificats d’interception du proxy, ou configurez un fichier de certificats valide pour Python.';

  @override
  String get settingsScraplingRuntimeCopiedAllLogs =>
      'Tous les journaux ont été copiés';

  @override
  String get settingsScraplingRuntimeCopyLogs => 'Copier les journaux';

  @override
  String get mcpStdioDialogProcessStatus => 'État du processus';

  @override
  String get mcpStdioDialogServiceConfig => 'Configuration du service';

  @override
  String get mcpStdioDialogType => 'Type';

  @override
  String get mcpStdioDialogCommand => 'Commande';

  @override
  String get mcpStdioDialogArgs => 'Arguments';

  @override
  String get mcpStdioDialogEnabled => 'Activé';

  @override
  String get mcpStdioDialogYes => 'Oui';

  @override
  String get mcpStdioDialogNo => 'Non';

  @override
  String get mcpStdioDialogEnvironment => 'Environnement';

  @override
  String get mcpStdioDialogError => 'Erreur';

  @override
  String get mcpStdioDialogDepsTitle => 'Gestion des dépendances';

  @override
  String get mcpStdioDialogNoDepsToManage =>
      'Ce service n’utilise pas de gestionnaire de paquets (npx / uvx). Aucune dépendance à gérer.';

  @override
  String mcpStdioDialogInstalledVersion(Object version) {
    return 'Installé v$version';
  }

  @override
  String get mcpStdioDialogUnknownVersion => '?';

  @override
  String get mcpStdioDialogNotGloballyInstalled => 'Non installé globalement';

  @override
  String get mcpStdioDialogInstall => 'Installer';

  @override
  String get mcpStdioDialogUpdate => 'Mettre à jour';

  @override
  String get mcpStdioDialogUninstall => 'Désinstaller';

  @override
  String mcpStdioDialogLatestVersion(Object version) {
    return 'Dernière version : $version';
  }

  @override
  String get mcpStdioDialogUpdateAvailableSuffix => ' (mise à jour disponible)';

  @override
  String get mcpStdioDialogOperationTimeout =>
      '[timeout] Opération expirée ; processus terminé';

  @override
  String mcpStdioDialogOperationCompleted(
    Object time,
    Object action,
    int exitCode,
  ) {
    return '[$time] ✓ $action terminé (code de sortie : $exitCode)';
  }

  @override
  String mcpStdioDialogOperationFailed(
    Object time,
    Object action,
    int exitCode,
  ) {
    return '[$time] ✗ Échec de $action (code de sortie : $exitCode)';
  }

  @override
  String mcpStdioDialogOperationFailedPlain(Object action, int exitCode) {
    return 'Échec de $action (code de sortie : $exitCode)';
  }

  @override
  String mcpStdioDialogOperationException(Object time, Object error) {
    return '[$time] ✗ Exception : $error';
  }

  @override
  String mcpStdioDialogWarmCache(Object time) {
    return '[$time] Préparation du cache isolé…';
  }

  @override
  String mcpStdioDialogWarmCacheDone(Object time) {
    return '[$time] ✓ Cache préparé';
  }

  @override
  String mcpStdioDialogWarmCacheSkipped(Object time, Object error) {
    return '[$time] Préparation du cache ignorée : $error';
  }

  @override
  String get mcpAutoProbeConcurrencyLabel => 'Parallélisme MCP check/fetch';

  @override
  String get mcpAutoProbeConcurrencyBody =>
      'Nombre maximal de services MCP vérifiés ou interrogés en parallèle. Valeur par défaut : 5. Réduisez-le pour limiter les ressources, augmentez-le pour accélérer de nombreux services.';

  @override
  String get mcpAutoProbeConcurrencySave => 'Enregistrer le parallélisme';

  @override
  String get mcpAutoProbeConcurrencySaved =>
      'Parallélisme MCP check/fetch enregistré.';

  @override
  String get mcpAutoProbeConcurrencyInvalid =>
      'Saisissez un entier entre 1 et 32.';

  @override
  String get mcpProbeDetailsTitle => 'Détails de sonde MCP';

  @override
  String get mcpProbePoolActive => 'Pool de sondes actif';

  @override
  String get mcpProbePoolIdle => 'Pool de sondes inactif';

  @override
  String get mcpProbePoolStatusTitle => 'État du pool';

  @override
  String mcpProbeSlots(int active, int total) {
    return 'Slots $active/$total';
  }

  @override
  String mcpProbeQueued(int count) {
    return 'En attente $count';
  }

  @override
  String get mcpProbeStateRunning => 'en cours';

  @override
  String get mcpProbeStateIdle => 'inactif';

  @override
  String mcpProbeToolsStatus(Object status) {
    return 'Outils $status';
  }

  @override
  String mcpProbeHealthStatus(Object status) {
    return 'Santé $status';
  }

  @override
  String mcpProbeLastRun(Object time) {
    return 'Dernier $time';
  }

  @override
  String mcpProbeNextRun(Object time) {
    return 'Prochain $time';
  }

  @override
  String get mcpProbeControlsTitle => 'Contrôles de sonde';

  @override
  String get mcpProbeForceProbe => 'Forcer la sonde';

  @override
  String get mcpProbeStopProbing => 'Arrêter la sonde';

  @override
  String get mcpProbeReloadServers => 'Recharger les services';

  @override
  String mcpProbeServerStatusTitle(int count) {
    return 'État des sondes serveur ($count services)';
  }

  @override
  String get mcpProbeNoServers => 'Aucun service';

  @override
  String get mcpProbeHealthHealthy => 'Sain';

  @override
  String get mcpProbeHealthUnhealthy => 'Anormal';

  @override
  String get mcpProbeHealthChecking => 'Vérification';

  @override
  String get mcpProbeHealthIdle => 'Inactif';

  @override
  String get mcpProbeDisableServerTooltip => 'Désactiver la sonde';

  @override
  String get mcpProbeEnableServerTooltip => 'Activer la sonde';

  @override
  String get mcpProbeNoProbe => 'Pas de sonde';

  @override
  String mcpProbeToolCount(int count) {
    return '$count outils';
  }

  @override
  String get mcpProbeThisServer => 'Sonder ce service';

  @override
  String get mcpRelativeJustNow => 'à l’instant';

  @override
  String mcpRelativeSecondsAgo(int seconds) {
    return 'il y a ${seconds}s';
  }

  @override
  String mcpRelativeMinutesAgo(int minutes) {
    return 'il y a ${minutes}m';
  }

  @override
  String mcpRelativeHoursAgo(int hours) {
    return 'il y a ${hours}h';
  }

  @override
  String mcpRelativeDaysAgo(int days) {
    return 'il y a ${days}j';
  }

  @override
  String get mcpRelativeImminent => 'imminent';

  @override
  String mcpRelativeInSeconds(int seconds) {
    return 'dans ${seconds}s';
  }

  @override
  String mcpRelativeInMinutes(int minutes) {
    return 'dans ${minutes}m';
  }

  @override
  String mcpRelativeInHours(int hours) {
    return 'dans ${hours}h';
  }

  @override
  String mcpRelativeInDays(int days) {
    return 'dans ${days}j';
  }

  @override
  String get mcpKeywordIndexUpdateModeLabel =>
      'Mode de mise à jour de l\'index de mots-clés';

  @override
  String get mcpKeywordIndexUpdateModeBody =>
      'Contrôle la reconstruction de l\'index inversé des mots-clés MCP. Démarrage à froid : ne charge que le cache disque au démarrage ; cliquez sur « Construire l\'index de mots-clés » pour rafraîchir. Intervalle : reconstruction périodique (valeur + unité) avec écrasement complet du cache. Heure quotidienne : reconstruction une fois par jour à l\'heure fixée. Les deux derniers partagent une seule tâche cron système pour éviter la fragmentation.';

  @override
  String get mcpKeywordIndexUpdateModeColdStart => 'Démarrage à froid';

  @override
  String get mcpKeywordIndexUpdateModeInterval => 'Intervalle';

  @override
  String get mcpKeywordIndexUpdateModeScheduled => 'Heure quotidienne';

  @override
  String get mcpKeywordIndexUpdateModeColdStartHint =>
      'Mode démarrage à froid : ne charge l\'index de mots-clés que depuis le disque au démarrage ; cliquez sur « Construire l\'index de mots-clés » pour rafraîchir manuellement. La tâche cron système reste désactivée.';

  @override
  String get mcpKeywordIndexIntervalValueLabel => 'Intervalle';

  @override
  String get mcpKeywordIndexIntervalUnitLabel => 'Unité';

  @override
  String get mcpKeywordIndexIntervalUnitMinute => 'Minute(s)';

  @override
  String get mcpKeywordIndexIntervalUnitHour => 'Heure(s)';

  @override
  String get mcpKeywordIndexIntervalUnitDay => 'Jour(s)';

  @override
  String mcpKeywordIndexScheduledLabel(String time) {
    return 'Reconstruction quotidienne à $time';
  }

  @override
  String get mcpKeywordIndexScheduledPickAction => 'Choisir l\'heure';

  @override
  String get commonClose => 'Fermer';

  @override
  String get commonRunInBackground => 'Exécuter en arrière-plan';

  @override
  String get mcpBuildKeywordIndex => 'Construire l’index des mots-clés';

  @override
  String get mcpKeywordIndexBuildTitle =>
      'Construction de l’index inversé des mots-clés';

  @override
  String get mcpKeywordIndexBuildStarting => 'Préparation…';

  @override
  String mcpKeywordIndexBuildProgress(
    int idx,
    int count,
    Object server,
    int tools,
  ) {
    return '$idx/$count : $server ($tools outils analysés)';
  }

  @override
  String mcpKeywordIndexBuildSummary(
    int servers,
    int tools,
    int keys,
    Object sec,
  ) {
    return 'Indexé $servers serveurs, $tools outils, $keys mots-clés en ${sec}s';
  }

  @override
  String mcpKeywordIndexBuildSkipped(int n) {
    return '$n serveurs sans catalogue prêt ignorés';
  }

  @override
  String get mcpKeywordIndexBuildFailed => 'Échec de la construction :';

  @override
  String get mcpLazyLoadingModeLabel => 'Chargement différé des outils MCP';

  @override
  String get mcpLazyLoadingModeBody =>
      'Contrôle si les descriptions des outils MCP sont compressées hors du prompt système : Désactivé = toujours développées ; Activé = toujours compressées et récupérées à la demande via ToolSearch ; Auto compresse uniquement quand le coût estimé en jetons dépasse le seuil.';

  @override
  String get mcpLazyLoadingModeDisabled => 'Désactivé';

  @override
  String get mcpLazyLoadingModeAuto => 'Auto';

  @override
  String get mcpLazyLoadingModeEnabled => 'Activé';

  @override
  String get mcpLazyLoadingThresholdLabel =>
      'Seuil de compression des outils MCP';

  @override
  String get mcpLazyLoadingThresholdBody =>
      'En mode Auto, le chargement différé s\'active lorsque le total estimé de jetons des descriptions d\'outils MCP dépasse cette valeur.';

  @override
  String get mcpLazyLoadingThresholdSave => 'Enregistrer le seuil';

  @override
  String get mcpLazyLoadingThresholdSaved =>
      'Seuil de chargement différé MCP enregistré.';

  @override
  String get mcpLazyLoadingThresholdInvalid =>
      'Veuillez saisir un entier entre 1000 et 1000000.';

  @override
  String get settingsHarnessToolSearchHistoryCapLabel =>
      'Limite d\'historique ToolSearch Harness';

  @override
  String get settingsHarnessToolSearchHistoryCapBody =>
      'Nombre maximum de phases Harness récentes pour lesquelles la boîte de dialogue de l\'historique ToolSearch conserve les entrées. Les anciennes phases sont supprimées (LRU).';

  @override
  String settingsHarnessToolSearchHistoryCapValue(int cap) {
    return 'Conserve actuellement les $cap dernière(s) phase(s)';
  }

  @override
  String settingsHarnessToolSearchHistoryCapRange(int min, int max) {
    return 'Plage : $min–$max (par défaut 8)';
  }

  @override
  String settingsHarnessToolSearchHistoryCapResetTooltip(int defaultCap) {
    return 'Réinitialiser à la valeur par défaut ($defaultCap)';
  }

  @override
  String get harnessCliLoginNoOutputHint =>
      '[Indice] La CLI n’a pas encore produit de sortie. Elle peut être en cours d’initialisation ou attendre une autorisation dans le navigateur.\n';

  @override
  String harnessCliLoginTimedOut(int minutes) {
    return 'La connexion a expiré après $minutes minutes. Le processus a été arrêté.';
  }

  @override
  String get harnessCliLoginTtyRequiredHint =>
      '[Indice] Cette CLI peut nécessiter un vrai terminal (TTY) pour la connexion interactive.\nUtilisez le bouton « Ouvrir dans le terminal » ci-dessous pour terminer la connexion dans le terminal système.\n';

  @override
  String harnessCliLoginStreamError(Object error) {
    return '[Erreur de flux : $error]';
  }

  @override
  String harnessCliLoginFailedToStartProcess(Object message) {
    return 'Impossible de démarrer le processus : $message';
  }

  @override
  String harnessCliLoginOpenTerminalError(Object error) {
    return '[Erreur lors de l’ouverture du terminal : $error]';
  }

  @override
  String get harnessCliLoginStatusFailed => 'Échec du lancement';

  @override
  String get harnessCliLoginStatusStarting =>
      'Démarrage du flux de connexion...';

  @override
  String get harnessCliLoginStatusFinished => 'Processus terminé';

  @override
  String harnessCliLoginStatusFinishedWithExit(int exitCode) {
    return 'Processus terminé · code $exitCode';
  }

  @override
  String get harnessCliLoginStatusWaiting =>
      'En attente d’interaction avec la CLI...';

  @override
  String harnessCliLoginTitle(Object name) {
    return 'Connexion $name';
  }

  @override
  String get harnessCliLoginDescription =>
      'Cette fenêtre exécute le flux de connexion CLI dans l’application. La CLI peut ouvrir votre navigateur externe pendant l’authentification.';

  @override
  String get harnessCliLoginCopyCommandTooltip => 'Copier la commande';

  @override
  String get harnessCliLoginEmptyOutput => 'En attente de sortie CLI...';

  @override
  String get harnessCliLoginInputLabel => 'Envoyer une saisie';

  @override
  String get harnessCliLoginInputHint =>
      'Saisissez une réponse puis appuyez sur Entrée ; laissez vide pour envoyer Entrée';

  @override
  String get harnessCliLoginSend => 'Envoyer';

  @override
  String get harnessCliLoginSendEsc => 'Envoyer Esc';

  @override
  String get harnessCliLoginOpenInTerminal => 'Ouvrir dans le terminal';

  @override
  String get harnessCliInstallLogSuccess => '✓ Installation réussie';

  @override
  String harnessCliInstallLogSuccessWithPath(Object path) {
    return '✓ Installation réussie (chemin : $path)';
  }

  @override
  String harnessCliInstallLogFailureExitCode(int exitCode) {
    return '✗ Échec de l’installation (code de sortie : $exitCode)';
  }

  @override
  String harnessCliInstallLogStartProcessFailed(Object message) {
    return '✗ Impossible de démarrer le processus d’installation : $message';
  }

  @override
  String harnessCliInstallLogGenericError(Object error) {
    return '✗ Erreur : $error';
  }

  @override
  String get harnessCliInstallHintInstallNode =>
      '  → Installez d’abord Node.js : https://nodejs.org';

  @override
  String get harnessCliInstallHintRetryAdminButton =>
      '  → Cliquez sur le bouton « Réessayer en administrateur » ci-dessous';

  @override
  String harnessCliInstallHintTrySudo(Object command) {
    return '  → Essayez : sudo $command';
  }

  @override
  String get harnessCliInstallHintCheckNetworkDocs =>
      '  → Vérifiez la connexion réseau ou consultez la documentation officielle';

  @override
  String get harnessCliInstallHintInstallPipx =>
      '  → Installez d’abord pipx : https://pipx.pypa.io/stable/installation/';

  @override
  String get harnessCliInstallHintUsePipInstallUserAider =>
      '    Ou utilisez : pip install --user aider-chat';

  @override
  String get harnessCliInstallHintHomebrewNoSudo =>
      '  → Homebrew ne devrait généralement pas être installé avec sudo ; vérifiez les permissions du dossier';

  @override
  String get harnessCliInstallHintHomebrewFix =>
      '  → Correction suggérée : https://docs.brew.sh/FAQ#why-does-homebrew-say-sudo-is-not-allowed';

  @override
  String get harnessCliInstallHintInstallPython =>
      '  → Installez d’abord Python : https://www.python.org';

  @override
  String harnessCliInstallHintPipInstallUser(Object packageName) {
    return '  → Essayez : pip install --user $packageName';
  }

  @override
  String harnessCliInstallHintOfficialDocs(Object url) {
    return '  → Documentation officielle : $url';
  }

  @override
  String get harnessCliInstallLogCancelled => '⚠ Installation annulée';

  @override
  String get harnessCliInstallWindowsAdminManual =>
      'Exécutez manuellement dans PowerShell avec les droits administrateur :';

  @override
  String harnessCliInstallAdminCommand(Object command) {
    return '> [Admin] $command';
  }

  @override
  String get harnessCliInstallAdminTimeout =>
      '✗ La fenêtre d’autorisation administrateur a expiré ou n’a pas démarré ; le sous-processus osascript a été arrêté de force';

  @override
  String get harnessCliInstallUserCancelledAuth => '⚠ Autorisation annulée';

  @override
  String get harnessCliInstallAdminPermissionFailed =>
      '✗ Impossible d’obtenir les droits administrateur';

  @override
  String harnessCliInstallPathMissingWarning(Object executable) {
    return '⚠ Installation terminée, mais $executable est introuvable dans le PATH actuel';
  }

  @override
  String get harnessCliInstallRestartPathHint =>
      '  → Essayez de redémarrer OpenHand ou de le lancer depuis un terminal pour charger le nouveau PATH';

  @override
  String get harnessCliInstallTimeoutManual =>
      '✗ Installation expirée (plus de 5 minutes). Exécutez manuellement :';

  @override
  String harnessCliInstallOsascriptStartFailed(Object message) {
    return '✗ Impossible de démarrer osascript : $message';
  }

  @override
  String get harnessCliInstallLinuxSudoManual =>
      'Exécutez manuellement dans un terminal (droits root requis) :';

  @override
  String get harnessCliInstallStatusInstalling => 'Installation...';

  @override
  String get harnessCliInstallStatusSuccess => 'Installation réussie';

  @override
  String get harnessCliInstallStatusCancelled => 'Annulé';

  @override
  String get harnessCliInstallStatusFailed => 'Échec de l’installation';

  @override
  String harnessCliInstallTitle(Object name) {
    return 'Installer $name';
  }

  @override
  String get harnessCliInstallCopyDocUrl => 'Copier l’URL de la doc';

  @override
  String get harnessCliInstallCancel => 'Annuler l’installation';

  @override
  String get harnessCliInstallRetryAdmin => 'Réessayer en admin';

  @override
  String get harnessCliInstallDoneContinue => 'Terminé, continuer';

  @override
  String get settingsToolSearchReplayCancelWindowLabel =>
      'Fenêtre d’annulation du replay';

  @override
  String get settingsToolSearchReplayCancelWindowBody =>
      'Délai d’attente de la snackbar avant l’envoi ; appuyez sur Annuler pour ignorer.';

  @override
  String settingsToolSearchReplayCancelWindowValue(int seconds) {
    return 'Fenêtre : $seconds s';
  }

  @override
  String settingsToolSearchReplayCancelWindowRange(int min, int max) {
    return 'Plage : $min–$max s (par défaut 3)';
  }

  @override
  String settingsToolSearchReplayCancelWindowResetTooltip(int defaultSeconds) {
    return 'Réinitialiser à la valeur par défaut ($defaultSeconds s)';
  }

  @override
  String get mcpLazyLoadingHowItWorks =>
      'Lorsque le chargement différé est actif, les descriptions des outils MCP sont repliées en un index de noms. L\'outil intégré ToolSearch récupère le schéma JSON complet à la demande via trois formes :\n• select:NAME (sélection directe, multi-sélection séparée par espaces)\n• mot-clé (scoré sur name/description)\n• +MOTCLE (terme requis pour filtrer le bruit)\nAprès une correspondance, ToolSearch est appelé avec le tool_name exact et des arguments conformes au schéma. La liste native reste fixe pour préserver le cache du prompt.';

  @override
  String get settingsGeneralSubtitle =>
      'Gérez le thème, la langue et les informations principales de l\'application.';

  @override
  String get settingsAiSubtitle =>
      'Gérer les modèles de chat, l’authentification et les adaptateurs de protocole.';

  @override
  String get settingsActiveToolCallsTitle => 'Appels d’outils actifs';

  @override
  String get settingsActiveToolCallsBody =>
      'Vue en direct de chaque appel d’outil distribué : PID, type, session associée et durée écoulée. Appuyez sur Stop pour interrompre uniquement cet appel.';

  @override
  String get settingsActiveToolCallsEmpty =>
      'Aucun appel d’outil n’est en cours d’exécution.';

  @override
  String get settingsActiveToolCallsCancel => 'Arrêter';

  @override
  String get settingsActiveToolKindBuiltin => 'Intégré';

  @override
  String get settingsActiveToolKindMcp => 'MCP';

  @override
  String get settingsActiveToolKindSkill => 'Skill';

  @override
  String get settingsActiveToolSessionLabel => 'session';

  @override
  String get settingsToolHardeningTitle =>
      'Paramètres de durcissement des outils';

  @override
  String get settingsToolHardeningBody =>
      'Durée d’arrêt gracieux des sous-processus, limite de sortie bash et limite d’appels d’outils simultanés.';

  @override
  String get settingsSubprocessGracefulShutdownLabel =>
      'Arrêt propre du sous-processus (ms)';

  @override
  String get settingsSubprocessGracefulShutdownBody =>
      'Temps d’attente entre SIGTERM et SIGKILL lors d’une annulation. Plus grand = plus indulgent, mais Stop semble plus lent. Plage 100–5000.';

  @override
  String get settingsBashOutputMaxBytesLabel => 'Limite de capture Bash (car.)';

  @override
  String get settingsBashOutputMaxBytesBody =>
      'Plafond stdout+stderr capturés par appel bash. Au-delà, troncature au milieu en gardant tête et queue. Plage 16000–4000000.';

  @override
  String get settingsMaxConcurrentToolsLabel => 'Appels d’outils concurrents';

  @override
  String get settingsMaxConcurrentToolsBody =>
      'Nombre maximal d’appels d’outils exécutés en parallèle dans une session. Plage 1–64.';

  @override
  String get settingsToolHardeningInvalid =>
      'Veuillez saisir un entier dans l’intervalle';

  @override
  String get settingsSkillsSubtitle =>
      'Gérez le dossier local des compétences, la création de modèles et les compétences installées.';

  @override
  String get settingsMemorySubtitle =>
      'Gérer le commutateur de mémoire utilisateur et le chemin du fichier de persistance.';

  @override
  String get settingsPersistenceInvalidTitle =>
      'Données de paramètres invalides';

  @override
  String get settingsPersistenceInvalidBody =>
      'L’enregistrement de la base de données est illisible. Les valeurs par défaut sont affichées sans écraser les données d’origine.';

  @override
  String get settingsPersistenceLoadFailedTitle =>
      'Échec de lecture des paramètres';

  @override
  String get settingsPersistenceLoadFailedBody =>
      'La base locale est inaccessible. Les valeurs par défaut sont affichées temporairement et l’enregistrement est suspendu.';

  @override
  String get settingsPersistenceSaveFailedTitle =>
      'Échec de l’enregistrement des paramètres';

  @override
  String get settingsPersistenceSaveFailedBody =>
      'L’écriture dans la base de paramètres a échoué. L’interface est revenue à la dernière configuration valide. Vérifiez l’accès à la base et le disque.';

  @override
  String get settingsPersistenceDismiss => 'Ignorer';

  @override
  String get settingsAnimationRestoreDefaultsTitle =>
      'Restaurer les animations';

  @override
  String get settingsAnimationRestoreDefaultsSubtitle =>
      'Réinitialise en une action le style d’entrée/sortie, la durée et la courbe des animations des boîtes de dialogue, menus, pages/modules, panneaux, chips et éléments de liste.';

  @override
  String get settingsAnimationRestoreDefaultsButton => 'Restaurer';

  @override
  String get settingsAnimationRestoreConfirmTitle =>
      'Restaurer les animations par défaut ?';

  @override
  String get settingsAnimationRestoreConfirmMessage =>
      'Toutes les animations des boîtes de dialogue, menus, pages/modules, panneaux, chips et éléments de liste seront réinitialisées. Les valeurs personnalisées seront remplacées.';

  @override
  String get settingsAnimationRestoreConfirm => 'Restaurer';

  @override
  String get settingsAnimationRestoreSuccess =>
      'Animations par défaut restaurées';

  @override
  String get settingsDialogAnimationTitle => 'Animation des dialogues';

  @override
  String get settingsDialogAnimationSubtitle =>
      'Configure le style d’entrée/sortie, la durée et la courbe de toutes les boîtes de dialogue.';

  @override
  String get settingsMenuAnimationTitle => 'Animation des menus';

  @override
  String get settingsMenuAnimationSubtitle =>
      'Configure le style d’entrée/sortie, la durée et la courbe des menus contextuels et déroulants.';

  @override
  String get settingsPanelAnimationTitle => 'Animation des panneaux';

  @override
  String get settingsPanelAnimationSubtitle =>
      'Configure les transitions des panneaux de l’espace de travail, comme navigation/fichiers à gauche et conversation/éditeur à droite. Les modules de droite utilisent l’animation de page.';

  @override
  String get settingsPageAnimationTitle => 'Animation page / module';

  @override
  String get settingsPageAnimationSubtitle =>
      'Configure les transitions du contenu principal à droite, notamment Workspace, Paramètres, MCP, Mémoire, Hooks, Crons, Compétences et Automatisations.';

  @override
  String get settingsChipAnimationTitle => 'Animation des chips';

  @override
  String get settingsChipAnimationSubtitle =>
      'Configure les animations d’entrée/sortie des chips amovibles : compétence sélectionnée, pièces jointes, références projet, messages en file, indicateur d’édition, etc.';

  @override
  String get settingsListItemAnimationTitle => 'Animation des listes';

  @override
  String get settingsListItemAnimationSubtitle =>
      'Configure l’animation d’entrée des éléments de liste comme serveurs MCP, mémoires, cartes d’instructions, sessions latérales et appels d’outils.';

  @override
  String get settingsAnimationEnter => 'Entrée';

  @override
  String get settingsAnimationExit => 'Sortie';

  @override
  String get settingsAnimationDuration => 'Durée';

  @override
  String get settingsAnimationCurve => 'Courbe';

  @override
  String get dialogAnimationStyleNone => 'Aucune';

  @override
  String get dialogAnimationStyleFade => 'Fondu';

  @override
  String get dialogAnimationStyleFadeScale => 'Fondu + zoom';

  @override
  String get dialogAnimationStyleSlideUp => 'Glisser haut';

  @override
  String get dialogAnimationStyleSlideDown => 'Glisser bas';

  @override
  String get dialogAnimationStyleSlideLeft => 'Glisser gauche';

  @override
  String get dialogAnimationStyleSlideRight => 'Glisser droite';

  @override
  String get dialogAnimationStyleExpand => 'Expansion';

  @override
  String get dialogAnimationStyleRotateScale => 'Rotation + zoom';

  @override
  String get dialogAnimationStyleElastic => 'Élastique';

  @override
  String get dialogAnimationStyleSpringScale => 'Ressort';

  @override
  String get dialogAnimationStyleFlipX => 'Flip X';

  @override
  String get dialogAnimationCurveEaseInOut => 'Ease In-Out';

  @override
  String get dialogAnimationCurveEaseOut => 'Ease Out';

  @override
  String get dialogAnimationCurveEaseOutCubic => 'Ease Out Cubic';

  @override
  String get dialogAnimationCurveEaseInOutCubicEmphasized => 'Cubic accentué';

  @override
  String get dialogAnimationCurveElasticOut => 'Elastic Out';

  @override
  String get dialogAnimationCurveBounceOut => 'Bounce Out';

  @override
  String get dialogAnimationCurveDecelerate => 'Décélération';

  @override
  String get commonOptional => 'Facultatif';

  @override
  String get cronScriptTypeCommand => 'Commande';

  @override
  String get cronScriptTypeScript => 'Script';

  @override
  String get cronScriptTypeAgent => 'Agent';

  @override
  String get cronJobStatusRunning => 'En cours';

  @override
  String get cronJobStatusPaused => 'En pause';

  @override
  String get cronJobStatusFailed => 'Echec';

  @override
  String get cronJobStatusError => 'Erreur';

  @override
  String get cronJobStatusIdle => 'Inactif';

  @override
  String get cronNotifyTypeNone => 'Aucune';

  @override
  String get cronNotifyTypeLog => 'Journal uniquement';

  @override
  String get cronNotifyTypeSystem => 'Notification systeme';

  @override
  String get cronNotifyTypeAppNotification => 'Notification dans l app';

  @override
  String get cronNotifySeverityInfo => 'Info';

  @override
  String get cronNotifySeveritySuccess => 'Succes';

  @override
  String get cronNotifySeverityWarning => 'Avertissement';

  @override
  String get cronNotifySeverityError => 'Erreur';

  @override
  String get cronNotifySeverityCritical => 'Critique';

  @override
  String get cronParserFieldCountError =>
      'L expression Cron doit contenir exactement 5 champs (min heure jour mois semaine)';

  @override
  String get cronParserFieldMinute => 'Minute';

  @override
  String get cronParserFieldHour => 'Heure';

  @override
  String get cronParserFieldDayOfMonth => 'Jour du mois';

  @override
  String get cronParserFieldDayOfMonthShort => 'Jour';

  @override
  String get cronParserFieldMonth => 'Mois';

  @override
  String get cronParserFieldDayOfWeek => 'Jour semaine';

  @override
  String get cronParserFieldDayOfWeekShort => 'Sem.';

  @override
  String cronParserInvalidField(String field, String value) {
    return 'Champ $field invalide \"$value\"';
  }

  @override
  String get cronsViewDescription =>
      'Configurez et gerez les taches planifiees. Prend en charge les expressions Cron, les delais, les nouvelles tentatives et l historique.';

  @override
  String get cronsNewCronJob => 'Nouvelle tache Cron';

  @override
  String get cronsEditCronJob => 'Modifier la tache Cron';

  @override
  String get cronsDeleteCronJobTitle => 'Supprimer la tache Cron';

  @override
  String cronsDeleteCronJobMessage(String name) {
    return 'Supprimer \"$name\" ? Cette action est irreversible. L historique d execution sera aussi supprime.';
  }

  @override
  String get cronsEmptyTitle => 'Aucune tache Cron configuree';

  @override
  String get cronsEmptyBody =>
      'Cliquez sur \"Nouvelle tache Cron\" ci-dessus pour commencer.';

  @override
  String get cronsCronExpressionTooltip => 'Expression Cron';

  @override
  String get cronsTimeoutTooltip => 'Delai';

  @override
  String get cronsRetryCountTooltip => 'Nombre de tentatives';

  @override
  String get cronsMcpKeywordIndexLockedTooltip =>
      'Controle par Parametres -> MCP -> Mode de mise a jour de l index de mots-cles';

  @override
  String get cronsRunOnceNow => 'Executer maintenant';

  @override
  String get cronsHistory => 'Historique';

  @override
  String cronsLastRunAt(String time) {
    return 'Derniere: $time';
  }

  @override
  String get cronsFieldName => 'Nom';

  @override
  String get cronsFieldNameHint => 'ex. Sauvegarde quotidienne';

  @override
  String get cronsFieldDescription => 'Description';

  @override
  String get cronsFieldType => 'Type';

  @override
  String get cronsFieldScriptFilePath => 'Chemin du script';

  @override
  String get cronsFieldScriptFilePathHint =>
      'Selectionnez un fichier .sh / .ps1 / .bat';

  @override
  String get cronsBrowse => 'Parcourir';

  @override
  String get cronsFieldCommand => 'Commande';

  @override
  String get cronsFieldCommandHintWindows =>
      'Entrez une commande PowerShell / BAT';

  @override
  String get cronsFieldCommandHintShell => 'Entrez une commande shell';

  @override
  String get cronsCronSchedule => 'Planification Cron';

  @override
  String get cronsCronScheduleHelper =>
      'Le champ secondes reste a 0. Granularite minimale: minute. Format: min heure jour mois semaine';

  @override
  String get cronsTimeoutSeconds => 'Delai (s)';

  @override
  String get cronsRetries => 'Tentatives';

  @override
  String get cronsMaxRetryDelaySeconds => 'Delai max entre tentatives (s)';

  @override
  String get cronsRunAsUser => 'Executer en tant que';

  @override
  String get cronsDefaultCurrentUser => 'Par defaut (utilisateur courant)';

  @override
  String get cronsDefault => 'Par defaut';

  @override
  String get cronsTagsCommaSeparated => 'Tags (separes par virgules)';

  @override
  String get cronsTagsHint => 'ex. sauvegarde, nettoyage';

  @override
  String get cronsWorkingDirectory => 'Dossier de travail';

  @override
  String get cronsWorkingDirectoryHint =>
      'Facultatif, dossier de l app par defaut';

  @override
  String get cronsEnvironmentVariables => 'Variables d environnement';

  @override
  String get cronsEnvironmentVariablesHint =>
      'Une par ligne, format: KEY=VALUE';

  @override
  String get cronsExecutionContextCollection =>
      'Collecte du contexte d execution';

  @override
  String get cronsCollectAppMetadata => 'Capturer les metadonnees app';

  @override
  String get cronsCollectAppMetadataSubtitle =>
      'Capture version, PID, chemin executable, etc.';

  @override
  String get cronsCollectHostMetadata => 'Capturer les metadonnees hote';

  @override
  String get cronsCollectHostMetadataSubtitle =>
      'Capture version OS, nom d hote, coeurs CPU, etc.';

  @override
  String get cronsCollectEnvironmentSnapshot =>
      'Capturer l instantane d environnement';

  @override
  String get cronsCollectEnvironmentSnapshotSubtitle =>
      'Capture les variables d environnement effectives (peut contenir des donnees sensibles).';

  @override
  String get cronsSensitive => 'Sensible';

  @override
  String get cronsNotificationSettings => 'Parametres de notification';

  @override
  String get cronsTestNotification => 'Tester la notification';

  @override
  String get cronsTestSuccessNotification => 'Tester la notification de succes';

  @override
  String get cronsTestFailureNotification => 'Tester la notification d echec';

  @override
  String get cronsTestTimeoutNotification => 'Tester la notification de delai';

  @override
  String get cronsTestAllNotifications => 'Tout tester (sequence)';

  @override
  String get cronsNotificationSettingsHelper =>
      'Chaque evenement peut configurer canal, severite, son et vibration independamment.';

  @override
  String get cronsOnSuccess => 'En cas de succes';

  @override
  String get cronsOnFailure => 'En cas d echec';

  @override
  String get cronsOnTimeout => 'En cas de delai';

  @override
  String get cronsEnabled => 'Active';

  @override
  String get cronsCustomNotificationMessageHint =>
      'Message personnalise (facultatif)';

  @override
  String get cronsVibrationUnsupportedHint =>
      'La vibration n est pas prise en charge sur cette plateforme et sera ignoree.';

  @override
  String get cronsValidationNameRequired => 'Entrez un nom de tache Cron.';

  @override
  String get cronsValidationScriptRequired => 'Selectionnez un script.';

  @override
  String get cronsValidationCommandRequired => 'Entrez une commande.';

  @override
  String cronsValidationInvalidEnvironment(String lines) {
    return 'Format de variable d environnement invalide ligne(s) $lines. Utilisez KEY=VALUE.';
  }

  @override
  String get cronsNotificationSequentialStartTitle =>
      'Debut du test sequentiel';

  @override
  String get cronsNotificationSequentialStartBody =>
      'Tests de notifications succes, echec et delai dans l ordre.';

  @override
  String get cronsNotificationVibrationIgnoredTitle => 'Vibration ignoree';

  @override
  String get cronsNotificationSequentialVibrationIgnoredBody =>
      'La vibration n est pas prise en charge ici et a ete ignoree pendant le test sequentiel.';

  @override
  String get cronsNotificationSequentialCompletedTitle =>
      'Test sequentiel termine';

  @override
  String get cronsNotificationSequentialCompletedBody =>
      'Tests de notifications succes, echec et delai termines.';

  @override
  String get cronsNotificationScenarioSuccess => 'Succes';

  @override
  String get cronsNotificationScenarioFailure => 'Echec';

  @override
  String get cronsNotificationScenarioTimeout => 'Delai';

  @override
  String get cronsNotificationScenarioAll => 'Tout';

  @override
  String cronsNotificationTestTitle(String label) {
    return 'Test de notification Cron - $label';
  }

  @override
  String get cronsNotificationTestDefaultBodySuccess =>
      'Message de test pour le succes.';

  @override
  String get cronsNotificationTestDefaultBodyFailure =>
      'Message de test pour l echec.';

  @override
  String get cronsNotificationTestDefaultBodyTimeout =>
      'Message de test pour le delai.';

  @override
  String get cronsNotificationNoEmitBody =>
      'Le reglage est Aucune ou Journal uniquement; aucune notification n est emise.';

  @override
  String get cronsSystemNotificationUnavailableTitle =>
      'Notification systeme indisponible';

  @override
  String get cronsSystemNotificationFallbackBody =>
      'La notification systeme a echoue; bascule vers une notification dans l app.';

  @override
  String get cronsNotificationVibrationIgnoredBody =>
      'La vibration n est pas prise en charge ici et a ete ignoree.';

  @override
  String get cronsUnknownPlatform => 'Plateforme inconnue';

  @override
  String get cronsToggleOn => 'Active';

  @override
  String get cronsToggleOff => 'Desactive';

  @override
  String get cronsSupportBestEffortSystemSound =>
      'Pris en charge (son systeme au mieux)';

  @override
  String get cronsSupportSupported => 'Pris en charge';

  @override
  String get cronsSupportNotSupportedOnPlatform =>
      'Non pris en charge sur cette plateforme';

  @override
  String get cronsSupportNotSupportedWillBeIgnored =>
      'Non pris en charge (sera ignore)';

  @override
  String get cronsSoundLabel => 'Son';

  @override
  String get cronsVibrationLabel => 'Vibration';

  @override
  String get cronsPlatformLabel => 'Plateforme';

  @override
  String get cronsSupportLabel => 'Support';

  @override
  String get cronsExecutionHistoryTitle => 'Historique d execution de la tache';

  @override
  String get cronsClearAllExecutionHistory => 'Effacer tout l historique';

  @override
  String get cronsNoExecutionRecords => 'Aucun enregistrement d execution';

  @override
  String get cronsClearExecutionHistoryTitle => 'Effacer l historique';

  @override
  String cronsClearExecutionHistoryMessage(String name) {
    return 'Effacer tout l historique pour \"$name\" ? Cette action est irreversible.';
  }

  @override
  String get cronsClear => 'Effacer';

  @override
  String get cronsDeleteExecutionRecordTitle => 'Supprimer l enregistrement';

  @override
  String get cronsDeleteExecutionRecordMessage =>
      'Supprimer cet enregistrement d execution ?';

  @override
  String get cronsExecutionStatusSuccess => 'Succes';

  @override
  String get cronsExecutionStatusFailed => 'Echec';

  @override
  String get cronsExecutionStatusTimedOut => 'Delai depasse';

  @override
  String get cronsExecutionStatusRunning => 'En cours';

  @override
  String get cronsExecutionStatusKilled => 'Arrete';

  @override
  String get cronsTriggerManual => 'Manuel';

  @override
  String get cronsTriggerScheduled => 'Planifie';

  @override
  String get cronsDeleteThisRecord => 'Supprimer cet enregistrement';

  @override
  String get cronsRetryAttempt => 'Tentative';

  @override
  String get cronsRunAs => 'Executer comme';

  @override
  String get cronsWorkingDir => 'Dossier travail';

  @override
  String get cronsScriptEnvironmentOverrides =>
      'Surcharges d environnement du script:';

  @override
  String get cronsEnvironmentSnapshot => 'Instantane d environnement:';

  @override
  String get cronsErrorReason => 'Erreur:';

  @override
  String get cronsStdout => 'stdout:';

  @override
  String get cronsStderr => 'stderr:';

  @override
  String get cronsExecutionContext => 'Contexte d execution:';

  @override
  String get cronsHermesTalkerReportTitle => 'Rapport Hermes Talker';

  @override
  String get cronsHermesNoEligibleSessions =>
      'Aucune session eligible n a ete apprise pendant ce cycle.';

  @override
  String cronsHermesAffectedSessions(int count) {
    return 'Sessions affectees ($count)';
  }

  @override
  String cronsHermesStatsLine(
    int scanned,
    int triggered,
    int skipped,
    int errors,
  ) {
    return 'analysees $scanned · declenchees $triggered · ignorees $skipped · erreurs $errors';
  }

  @override
  String get cronsHermesUntitledSession => '(session sans titre)';

  @override
  String cronsHermesMemoryUpdates(int count) {
    return 'memoire +$count';
  }

  @override
  String cronsHermesMemoryErrors(int count) {
    return 'erreurs memoire $count';
  }

  @override
  String cronsHermesSkillUpdates(int count) {
    return 'skill +$count';
  }

  @override
  String cronsHermesSkillErrors(int count) {
    return 'erreurs skill $count';
  }

  @override
  String cronsHermesProfileChanges(int count) {
    return 'profil $count';
  }

  @override
  String cronsHermesToolRounds(int count) {
    return 'tours $count';
  }

  @override
  String get cronsHermesModelLabel => 'modele';

  @override
  String get cronsHermesProviderLabel => 'fournisseur';

  @override
  String get cronsHermesTerminatedLabel => 'termine';

  @override
  String get cronsHermesUserProfileChanges =>
      'Changements du profil utilisateur';

  @override
  String get cronsHermesMemoryChanges => 'Changements de memoire';

  @override
  String get cronsHermesSkillChanges => 'Changements de skills';

  @override
  String get cronsHermesAiReasoningOnScene => 'Raisonnement IA sur place';

  @override
  String get cronsHermesAiResponseOnScene => 'Reponse IA sur place';

  @override
  String get cronsHermesNoFurtherDetails => 'Aucun autre detail.';

  @override
  String get cronsHermesStatusError => 'erreur';

  @override
  String get cronsHermesStatusSkipped => 'ignore';

  @override
  String get cronsHermesStatusOk => 'ok';

  @override
  String get cronsHermesChangeBefore => 'avant';

  @override
  String get cronsHermesChangeAfter => 'apres';

  @override
  String get cronsHermesChangeValue => 'valeur';

  @override
  String get cronsHermesChangeSource => 'source';

  @override
  String get cronsHermesChangeReason => 'raison';

  @override
  String get cronsHermesChangeMetadata => 'metadonnees';

  @override
  String get cronsHermesChangeError => 'erreur';

  @override
  String get cronsCollapse => 'Reduire';

  @override
  String get cronsExpand => 'Developper';

  @override
  String get aiModelAdd => 'Ajouter un fournisseur';

  @override
  String get aiModelsEmptyTitle => 'Aucun fournisseur de modèle pour l’instant';

  @override
  String get aiModelsEmptyBody =>
      'Ajoutez ici au moins une configuration de fournisseur de modèle, et l’éditeur de fil la réutilisera directement.';

  @override
  String get aiModelDialogCreateTitle => 'Ajouter un fournisseur de modèle';

  @override
  String get aiModelDialogEditTitle => 'Modifier le fournisseur de modèle';

  @override
  String get aiModelBaseUrl => 'URL de base';

  @override
  String get aiModelBaseUrlRequired => 'Saisissez une URL de base.';

  @override
  String get aiModelBaseUrlInvalid => 'Saisissez une URL de base valide.';

  @override
  String get aiModelOfficialWebsiteUrl => 'URL du site officiel (facultatif)';

  @override
  String get aiModelOfficialWebsiteUrlHint => 'https://example.com';

  @override
  String get aiModelOfficialWebsiteUrlInvalid =>
      'Saisissez une URL de site valide.';

  @override
  String get aiModelOpenWebsiteFailure => 'Impossible d’ouvrir le site.';

  @override
  String get aiModelOpenWebsiteTooltip => 'Ouvrir le site';

  @override
  String get aiModelAuthScheme => 'Schéma d’authentification';

  @override
  String get aiModelToken => 'Jeton';

  @override
  String get aiModelProtocol => 'Protocole';

  @override
  String get aiModelSaveSuccess =>
      'Configuration du fournisseur de modèle enregistrée.';

  @override
  String get aiModelDeleteConfirmTitle => 'Supprimer le fournisseur de modèle';

  @override
  String get aiModelDeleteConfirmBody =>
      'Supprimer cette configuration de fournisseur de modèle ?';

  @override
  String get aiModelDeleteSuccess =>
      'Configuration du fournisseur de modèle supprimée.';

  @override
  String get aiModelMoveUp => 'Monter';

  @override
  String get aiModelMoveDown => 'Descendre';

  @override
  String get aiModelSelected => 'Fournisseur de modèle actif';

  @override
  String get aiModelNoToken => 'Aucun jeton configuré';

  @override
  String get aiModelTest => 'Tester';

  @override
  String get aiModelTesting => 'Test en cours';

  @override
  String aiModelTestSuccess(String modelName) {
    return '$modelName a réussi le test.';
  }

  @override
  String aiModelTestFailure(String modelName, String reason) {
    return 'Échec du test de $modelName : $reason';
  }

  @override
  String get aiModelSelectionRequired =>
      'Ajoutez et sélectionnez d’abord un fournisseur de modèle IA dans les paramètres.';

  @override
  String get aiModelScanButton => 'Analyser les modèles';

  @override
  String get aiModelScanning => 'Analyse des modèles disponibles…';

  @override
  String get aiModelAvailableModels => 'Modèles disponibles';

  @override
  String get aiModelManualIdHint => 'Ajouter un ID de modèle manuellement';

  @override
  String get aiModelManualIdAdd => 'Ajouter';

  @override
  String aiModelCount(int count) {
    return '$count modèles';
  }

  @override
  String get chatModelButton => 'Choisir un modèle';

  @override
  String get aiAuthNone => 'Aucun';

  @override
  String get aiAuthBearer => 'Bearer';

  @override
  String get aiAuthToken => 'Jeton';

  @override
  String get aiAuthApiKey => 'Clé API';

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
  String get skillsPageTitle => 'Compétences';

  @override
  String get skillsPageSubtitle =>
      'Donnez à OpenHand une plus grande extensibilité grâce à une vue unifiée des compétences locales installées et des modèles.';

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
  String get skillsNoResultsTitle => 'Aucune compétence correspondante';

  @override
  String get skillsNoResultsBody =>
      'Essayez un autre mot-clé ou effacez la recherche pour revoir toutes les compétences.';

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
  String get skillsCreateDialogTitle => 'Créer une compétence';

  @override
  String get skillsCreateNameLabel => 'Nom de la compétence';

  @override
  String get skillsCreateNameRequired => 'Saisissez le nom de la compétence.';

  @override
  String get skillsCreateIconLabel => 'Icône de la compétence';

  @override
  String get skillsCreateIconHint => 'Choisissez un emoji ou une image locale.';

  @override
  String get skillsCreateIconRequired => 'Choisissez une icône.';

  @override
  String get skillsCreateIconChoose => 'Choisir un emoji';

  @override
  String get skillsCreateIconChange => 'Modifier';

  @override
  String get skillsCreateImageChoose => 'Choisir une image';

  @override
  String get skillsCreateImageChange => 'Remplacer l’image';

  @override
  String get skillsCreateImageSelected => 'Image locale sélectionnée';

  @override
  String get skillsCreateDescriptionLabel => 'Description courte';

  @override
  String get skillsCreateDescriptionRequired =>
      'Saisissez la description courte.';

  @override
  String get skillsCreateContentRequired => 'Saisissez le contenu de SKILL.md.';

  @override
  String get imageEditorTitle => 'Modifier l’image';

  @override
  String get imageEditorCropHint =>
      'Faites glisser l’image pour repositionner la zone de recadrage carrée, puis ajustez le zoom, la rotation, la luminosité et le contraste.';

  @override
  String get imageEditorZoomLabel => 'Zoom';

  @override
  String get imageEditorBrightnessLabel => 'Luminosité';

  @override
  String get imageEditorContrastLabel => 'Contraste';

  @override
  String get imageEditorRotateLeft => 'Rotation à gauche';

  @override
  String get imageEditorRotateRight => 'Rotation à droite';

  @override
  String get imageEditorReset => 'Réinitialiser';

  @override
  String get imageEditorLoadFailed =>
      'Impossible de charger l’image sélectionnée.';

  @override
  String get imageEditorProcessFailed =>
      'Impossible de traiter l’image sélectionnée.';

  @override
  String get imageEditorSectionColor =>
      'Couleur (température / teinte / gamma)';

  @override
  String get imageEditorSectionSplitToning => 'Tonalité fractionnée (HSL)';

  @override
  String get imageEditorSectionDetail =>
      'Détail (clarté / netteté / réduction du bruit / grain)';

  @override
  String get imageEditorSectionEffects =>
      'Effets (dispersion / distorsion / vignette)';

  @override
  String get imageEditorSectionWatermark => 'Filigrane texte / marque';

  @override
  String get imageEditorTemperatureLabel => 'Température';

  @override
  String get imageEditorTintLabel => 'Décalage de teinte';

  @override
  String get imageEditorGammaLabel => 'Gamma (courbe)';

  @override
  String get imageEditorShadowHueLabel => 'Teinte des ombres';

  @override
  String get imageEditorShadowStrengthLabel => 'Force des ombres';

  @override
  String get imageEditorHighlightHueLabel => 'Teinte des hautes lumières';

  @override
  String get imageEditorHighlightStrengthLabel => 'Force des hautes lumières';

  @override
  String get imageEditorClarityLabel => 'Clarté';

  @override
  String get imageEditorSharpnessLabel => 'Netteté';

  @override
  String get imageEditorDenoiseLabel => 'Réduction du bruit';

  @override
  String get imageEditorGrainLabel => 'Grain';

  @override
  String get imageEditorDispersionLabel => 'Dispersion';

  @override
  String get imageEditorDistortLabel =>
      'Distorsion (positif bombe / négatif étire)';

  @override
  String get imageEditorWatermarkTextLabel => 'Texte du filigrane';

  @override
  String get imageEditorWatermarkTextHint =>
      'Saisissez le texte à superposer (laisser vide pour ignorer)';

  @override
  String get imageEditorWatermarkSizeLabel => 'Taille du texte';

  @override
  String get imageEditorWatermarkOpacityLabel => 'Opacité';

  @override
  String get imageEditorWatermarkPositionLabel => 'Position';

  @override
  String get imageEditorAdvancedApplyHint =>
      'Les réglages des panneaux étendus sont appliqués à l’image d’origine lors de l’enregistrement.';

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
  String get skillsStorageStatusError =>
      'Impossible de lire le dossier des compétences';

  @override
  String get skillsPathSaved =>
      'L\'emplacement des compétences a été mis à jour';

  @override
  String get instructionPageTitle => 'Instructions';

  @override
  String get instructionPageSubtitle =>
      'Gérez des fragments de prompt réutilisables. Les instructions activées sont injectées dans chaque prompt système selon l\'ordre actuel et apparaissent au-dessus du composeur sous forme de puces activables pour un seul envoi.';

  @override
  String get instructionRefresh => 'Actualiser';

  @override
  String get instructionNewEntry => 'Nouvelle instruction';

  @override
  String get instructionEmptyTitle => 'Aucune instruction pour le moment';

  @override
  String get instructionEmptyBody =>
      'Créez la première instruction réutilisable. OpenHand la conservera dans le stockage local des instructions.';

  @override
  String get instructionLoadFailedTitle =>
      'Impossible de charger les instructions';

  @override
  String get instructionDeleteConfirmTitle => 'Supprimer l\'instruction';

  @override
  String get instructionDeleteConfirmBody =>
      'Supprimer cette instruction ? Cette action est irréversible.';

  @override
  String get instructionEnabledStatus => 'Activée et injectée';

  @override
  String get instructionDisabledStatus => 'Désactivée';

  @override
  String get instructionApplyToChipLabel => 'S\'applique à';

  @override
  String get instructionNotesChipLabel => 'Notes';

  @override
  String get instructionDialogCreateTitle => 'Nouvelle instruction';

  @override
  String get instructionDialogEditTitle => 'Modifier l\'instruction';

  @override
  String get instructionEnabledLabel => 'Activée';

  @override
  String get instructionEnabledBody =>
      'Injecter cette instruction dans la chaîne de prompt active.';

  @override
  String get instructionNameField => 'Nom *';

  @override
  String get instructionNameRequired => 'Saisissez un nom.';

  @override
  String get instructionDescriptionField => 'Description';

  @override
  String get instructionVersionField => 'Version';

  @override
  String get instructionApplyToField =>
      'S\'applique à (décrire quand charger cette instruction)';

  @override
  String get instructionTaskTypesField =>
      'Types de tâches déclencheurs (séparés par des virgules)';

  @override
  String get instructionKeywordsField =>
      'Mots-clés déclencheurs (séparés par des virgules)';

  @override
  String get instructionNotesField => 'Notes (une par ligne)';

  @override
  String get instructionBodyField => 'Corps de l\'instruction * (Markdown)';

  @override
  String get instructionBodyRequired => 'Saisissez le corps de l\'instruction.';

  @override
  String get instructionCreateAction => 'Créer';

  @override
  String get instructionSaveFailed =>
      'Échec de l\'enregistrement. Vérifiez que les champs obligatoires ne sont pas vides.';

  @override
  String get memoryPageTitle => 'Mémoire';

  @override
  String get memoryPageSubtitle =>
      'Gérez les mémoires utilisateur stockées dans la base de données locale.';

  @override
  String get memoryRefresh => 'Actualiser';

  @override
  String get memoryNewEntry => 'Nouvelle mémoire';

  @override
  String get memoryEmptyTitle => 'Aucune mémoire utilisateur pour l’instant';

  @override
  String get memoryEmptyBody =>
      'Ajoutez une mémoire utilisateur et OpenHand l’enregistrera dans la base locale.';

  @override
  String get memoryLoadFailedTitle => 'Échec du chargement des mémoires';

  @override
  String get memoryLoadFailedBody =>
      'Les données sont invalides ou indisponibles. Réparez ou effacez le stockage, puis réessayez.';

  @override
  String get memoryQuotaRecoveryTitle => 'Le stockage dépasse le quota';

  @override
  String get memoryQuotaRecoveryBody =>
      'Seul un aperçu limité est affiché. Supprimez ou réduisez des entrées ; les nouvelles entrées sont temporairement désactivées.';

  @override
  String get memoryOperationFailed =>
      'L’action de mémoire a échoué. Veuillez réessayer.';

  @override
  String get memoryDialogCreateTitle => 'Ajouter une mémoire utilisateur';

  @override
  String get memoryDialogEditTitle => 'Modifier la mémoire utilisateur';

  @override
  String get memoryContentField => 'Contenu de la mémoire';

  @override
  String get memoryContentRequired => 'Saisissez le contenu de la mémoire.';

  @override
  String get memoryTagsField => 'Étiquettes';

  @override
  String get memoryTagsHint =>
      'Saisissez une étiquette et appuyez sur Entrée pour l’ajouter';

  @override
  String get memoryTagLimitExceeded =>
      'Une mémoire peut contenir au maximum 32 tags.';

  @override
  String get memoryDeleteConfirmTitle => 'Supprimer la mémoire utilisateur';

  @override
  String get memoryDeleteConfirmBody =>
      'Supprimer cette mémoire utilisateur ? Cette action est irréversible.';

  @override
  String get memoryTypeUser => 'Modifié par l’utilisateur';

  @override
  String get memoryEntryCreated => 'Mémoire utilisateur créée.';

  @override
  String get memoryEntryUpdated => 'Mémoire utilisateur mise à jour.';

  @override
  String get memoryEntryDeleted => 'Mémoire utilisateur supprimée.';

  @override
  String get memoryEnabledLabel => 'Activer la mémoire';

  @override
  String get memoryEnabledBody =>
      'Lorsque désactivé, les mémoires utilisateur enregistrées restent sur le disque mais ne sont pas utilisées à l’exécution.';

  @override
  String get userMemoryFileLabel => 'Base des mémoires';

  @override
  String get memoryFileBody =>
      'Les mémoires utilisateur sont stockées dans la base SQLite locale d’OpenHand.';

  @override
  String get memoryFileDefaultPath => 'Emplacement de la base';

  @override
  String get memoryOpenDirectory => 'Ouvrir le dossier de la base';

  @override
  String get memoryDisabledTitle => 'La mémoire est actuellement désactivée';

  @override
  String get memoryDisabledBody =>
      'Vous pouvez toujours gérer ici les mémoires utilisateur. Pour les utiliser à l’exécution, activez la mémoire dans Paramètres > Mémoire.';

  @override
  String get memoryCreatedAtLabel => 'Créé le';

  @override
  String get memoryPersistenceSaveFailedTitle =>
      'Échec de l’enregistrement de la mémoire';

  @override
  String get memoryPersistenceSaveFailedBody =>
      'L’écriture dans la base des mémoires a échoué. Aucune modification non validée n’a été appliquée. Vérifiez l’accès et le disque.';

  @override
  String get mcpPageTitle => 'MCP';

  @override
  String get mcpPageSubtitle =>
      'Gérez les configurations locales du serveur MCP avec une mise en page de style Cursor adaptée à OpenHand.';

  @override
  String get mcpRefresh => 'Actualiser';

  @override
  String get mcpNewServer => 'Nouveau serveur';

  @override
  String get mcpEmptyTitle => 'Aucun service MCP configuré pour l’instant';

  @override
  String get mcpEmptyBody =>
      'Ajoutez d’abord un serveur MCP. OpenHand l’enregistrera dans ~/.openhand/mcp/mcp_servers.json.';

  @override
  String get mcpLoadFailedTitle =>
      'Échec du chargement de la configuration MCP';

  @override
  String get mcpOperationFailed => 'L’action MCP a échoué. Veuillez réessayer.';

  @override
  String get mcpDialogCreateTitle => 'Ajouter un service MCP';

  @override
  String get mcpDialogEditTitle => 'Modifier le service MCP';

  @override
  String get mcpNameField => 'Nom du service';

  @override
  String get mcpNameRequired => 'Saisissez un nom de service.';

  @override
  String get mcpNameDuplicate => 'Ce nom de service existe déjà.';

  @override
  String get mcpTypeField => 'Type de service';

  @override
  String get mcpUrlField => 'URL du service';

  @override
  String get mcpUrlRequired => 'Saisissez une URL de service.';

  @override
  String get mcpUrlInvalid => 'Saisissez une URL de service valide.';

  @override
  String get mcpCommandField => 'Commande de lancement';

  @override
  String get mcpCommandRequired => 'Saisissez une commande de lancement.';

  @override
  String get mcpArgsField => 'Arguments de la commande';

  @override
  String get mcpArgsHint => 'Un argument par ligne';

  @override
  String get mcpServerEnabledLabel => 'Activer ce service';

  @override
  String get mcpServerEnabledBody =>
      'Lorsque désactivé, la configuration du service est conservée mais le serveur n’est pas activé à l’exécution.';

  @override
  String get mcpServerStatusEnabled => 'Activé';

  @override
  String get mcpServerStatusDisabled => 'Désactivé';

  @override
  String get mcpServerCreated => 'Service MCP créé.';

  @override
  String get mcpServerUpdated => 'Service MCP mis à jour.';

  @override
  String get mcpServerDeleted => 'Service MCP supprimé.';

  @override
  String get mcpDeleteConfirmTitle => 'Supprimer le service MCP';

  @override
  String get mcpDeleteConfirmBody =>
      'Supprimer cette configuration de service MCP ?';

  @override
  String mcpDeleteAlsoUninstallPackage(String packageName) {
    return 'Désinstaller aussi le paquet ($packageName)';
  }

  @override
  String get mcpDeleteAlsoUninstallPackageBody =>
      'Désinstalle le paquet global et nettoie le cache isolé.';

  @override
  String mcpDependencyCleanedUp(String packageName) {
    return 'Dépendance $packageName nettoyée';
  }

  @override
  String mcpDependencyCleanupFailed(String packageName, String error) {
    return 'Nettoyage de $packageName échoué : $error';
  }

  @override
  String mcpDependencyCleanupError(String packageName, String error) {
    return 'Erreur de nettoyage de $packageName : $error';
  }

  @override
  String get mcpTemplateSessionManaged => 'géré par session';

  @override
  String mcpTemplateSessionOn(String status) {
    return 'session active · $status';
  }

  @override
  String mcpTemplateSessionOff(String status) {
    return 'session inactive · $status';
  }

  @override
  String get mcpTemplateNotRegistered => 'non enregistré';

  @override
  String mcpTemplateRuntimeEnabledCount(int count) {
    return '$count sessions actives';
  }

  @override
  String get mcpDisabledTitle =>
      'Les services MCP sont actuellement désactivés';

  @override
  String get mcpDisabledBody =>
      'Vous pouvez toujours gérer ici les configurations de service. Pour les activer à l’exécution, activez le commutateur MCP dans Paramètres > MCP.';

  @override
  String get mcpTransportStreamableHttp => 'HTTP en flux';

  @override
  String get mcpTransportSse => 'SSE';

  @override
  String get mcpTransportStdio => 'STDIO';

  @override
  String get mcpPersistenceSaveFailedTitle =>
      'Échec de l’enregistrement de la configuration MCP';

  @override
  String get mcpPersistenceSaveFailedBody =>
      'L’écriture du fichier de configuration MCP a échoué. L’interface est revenue à la dernière configuration valide. Vérifiez les autorisations du fichier ou l’état du disque.';

  @override
  String get threadsEmptyBody =>
      'Aucun fil de conversation pour l’instant. Créez un nouveau fil pour commencer.';

  @override
  String get threadTemplateDialogTitle => 'Choisir un modèle de fil';

  @override
  String get threadTemplateDialogBody =>
      'Démarrez un nouveau fil en choisissant l’un des modèles de fonctionnalités intégrés ci-dessous.';

  @override
  String get threadCompressionNotice =>
      'Les anciens messages de ce fil ont été compressés en un point de contrôle de résumé pour garder l’invite active concentrée.';

  @override
  String get threadCompressionCheckpointLabel => 'Point de contrôle de résumé';

  @override
  String get aiCompressionThresholdLabel => 'Seuil de compression des messages';

  @override
  String get aiCompressionThresholdBody =>
      'Lorsque les messages historiques non compressés du fil actuel dépassent ce seuil de caractères, OpenHand résume la portion la plus ancienne en un point de contrôle de compression et garde la portion la plus récente active.';

  @override
  String get aiCompressionThresholdSave => 'Enregistrer le seuil';

  @override
  String get aiCompressionThresholdSaved =>
      'Le seuil de compression des messages IA a été mis à jour.';

  @override
  String get aiCompressionThresholdInvalid =>
      'Saisissez un seuil entier positif valide.';

  @override
  String get aiToolResultCompressionThresholdLabel =>
      'Seuil de compression de la sortie d’appel d’outil';

  @override
  String get aiToolResultCompressionThresholdSave => 'Enregistrer le seuil';

  @override
  String get aiToolResultCompressionThresholdSaved =>
      'Le seuil de compression de la sortie d’appel d’outil a été mis à jour.';

  @override
  String get aiToolResultCompressionThresholdInvalid =>
      'Saisissez un seuil entier positif valide.';

  @override
  String get aiToolResultCompressionEnabledLabel =>
      'Activer la compression de la sortie d’appel d’outil';

  @override
  String get aiToolResultCompressionEnabledBody =>
      'Détermine si les longues sorties d’outils sont résumées lors de la création des points de compression. Les conversations normales transmettent toujours les résultats complets au modèle ; la désactivation conserve aussi la sortie brute dans les points de compression et peut augmenter leur coût.';

  @override
  String get aiMicroCompressionEnabledLabel => 'Micro-Compression';

  @override
  String get aiMicroCompressionEnabledBody =>
      'Lorsqu’elle est activée, les anciens résultats d’outils consommés sont compactés uniquement dans les invites de point de compression. Cela réduit le coût du résumé et garde l’historique actif stable pour le cache. Lorsqu’elle est désactivée, les anciens résultats longs suivent toujours le résumé par seuil ci-dessus.';

  @override
  String get aiMessageContentSectionLabel => 'Contenu du message';

  @override
  String get aiMessageContentFormatLabel => 'Format de contenu';

  @override
  String get aiMessageContentFormatBody =>
      'Contrôle le rendu des messages de l’assistant IA. Markdown est la valeur par défaut ; Texte brut est le plus rapide ; HTML utilise un moteur tiers (coût en tokens un peu plus élevé) et retombe selon la règle ci-dessous en cas d’échec.';

  @override
  String get aiMessageContentFormatMarkdown => 'Markdown';

  @override
  String get aiMessageContentFormatPlainText => 'Texte brut';

  @override
  String get aiMessageContentFormatHtml => 'HTML';

  @override
  String get aiMessageContentFormatHtmlTokenWarning =>
      'Le mode HTML injecte des contraintes supplémentaires dans chaque prompt ; le coût en tokens est légèrement plus élevé.';

  @override
  String get aiHtmlRenderFallbackLabel => 'Repli de rendu HTML';

  @override
  String get aiHtmlRenderFallbackBody =>
      'Stratégie utilisée en cas d’échec du parsing ou du rendu HTML. Markdown ré-analyse en Markdown ; Texte brut affiche le texte tel quel.';

  @override
  String get aiHtmlRenderFallbackMarkdown => 'Markdown';

  @override
  String get aiHtmlRenderFallbackPlainText => 'Texte brut';

  @override
  String get aiHtmlContentRichnessLabel => 'Richesse du contenu HTML';

  @override
  String get aiHtmlContentRichnessBody =>
      'Contrôle l\'intensité visuelle injectée dans le modèle en mode HTML. Équilibré est le défaut (niveaux de gris sobres) ; Riche libère couleurs et cartes ; Vif pousse dégradés, glassmorphisme et blocs héro à l\'extrême — coût en tokens le plus élevé.';

  @override
  String get aiHtmlContentRichnessBalanced => 'Équilibré';

  @override
  String get aiHtmlContentRichnessRich => 'Riche';

  @override
  String get aiHtmlContentRichnessVivid => 'Vif';

  @override
  String get aiToolResultCompressionHeadTailWindowLabel =>
      'Fenêtre début/fin de compression';

  @override
  String get aiToolResultCompressionHeadTailWindowBody =>
      'Nombre de caractères de début/fin de la sortie brute conservés dans le résumé condensé. Par défaut 256 ; 0 désactive les extraits début/fin ; plage 0–8192.';

  @override
  String get aiToolResultCompressionHeadTailWindowSave =>
      'Enregistrer la fenêtre';

  @override
  String get aiToolResultCompressionHeadTailWindowSaved =>
      'Fenêtre début/fin mise à jour.';

  @override
  String get aiToolResultCompressionHeadTailWindowInvalid =>
      'Saisissez un entier entre 0 et 8192.';

  @override
  String get aiToolResultCompressionMaxPathHitsLabel =>
      'Limite d’extraction de chemins de compression';

  @override
  String get aiToolResultCompressionMaxPathHitsBody =>
      'Nombre maximal de chemins de fichiers affectés extraits dans le résumé. Par défaut 12 ; 0 désactive l’extraction ; plage 0–200.';

  @override
  String get aiToolResultCompressionMaxPathHitsSave => 'Enregistrer la limite';

  @override
  String get aiToolResultCompressionMaxPathHitsSaved =>
      'Limite d’extraction de chemins mise à jour.';

  @override
  String get aiToolResultCompressionMaxPathHitsInvalid =>
      'Saisissez un entier entre 0 et 200.';

  @override
  String get aiWriteToolSummaryMaxCharsLabel =>
      'Limite de caractères du résumé d’outil Write';

  @override
  String get aiWriteToolSummaryMaxCharsBody =>
      'Caractères maximaux de result_text conservés dans les résumés d’outils de type écriture (write/edit/multiedit/notebookedit/bash de type write). Par défaut 280 ; 0 omet le résumé ; plage 0–8192.';

  @override
  String get aiWriteToolSummaryMaxCharsSave => 'Enregistrer la limite';

  @override
  String get aiWriteToolSummaryMaxCharsSaved =>
      'Limite de caractères du résumé d’outil Write mise à jour.';

  @override
  String get aiWriteToolSummaryMaxCharsInvalid =>
      'Saisissez un entier entre 0 et 8192.';

  @override
  String get aiMaxRecentErrorsLabel =>
      'Conservation des erreurs récentes de session';

  @override
  String get aiMaxRecentErrorsBody =>
      'Nombre d’enregistrements d’erreurs récentes conservés dans l’état de session IA. Par défaut 20 ; plage 0–1000.';

  @override
  String get aiMaxRecentErrorsSave => 'Enregistrer la limite';

  @override
  String get aiMaxRecentErrorsSaved =>
      'Conservation des erreurs récentes de session mise à jour.';

  @override
  String get aiMaxRecentErrorsInvalid => 'Saisissez un entier entre 0 et 1000.';

  @override
  String get aiMaxPlanHistoryEntriesLabel =>
      'Conservation de l’historique des plans';

  @override
  String get aiMaxPlanHistoryEntriesBody =>
      'Nombre maximal d’entrées conservées dans plan_history en mode Plan. Par défaut 20 ; plage 0–1000.';

  @override
  String get aiMaxPlanHistoryEntriesSave => 'Enregistrer la limite';

  @override
  String get aiMaxPlanHistoryEntriesSaved =>
      'Conservation de l’historique des plans mise à jour.';

  @override
  String get aiMaxPlanHistoryEntriesInvalid =>
      'Saisissez un entier entre 0 et 1000.';

  @override
  String get aiMaxTruncationContinuationsLabel =>
      'Limite de continuation automatique';

  @override
  String get aiMaxTruncationContinuationsBody =>
      'Nombre maximal de continuations automatiques consécutives après que la sortie du modèle a été tronquée (finish_reason=length). Par défaut 5 ; plage 0–100.';

  @override
  String get aiMaxTruncationContinuationsSave => 'Enregistrer la limite';

  @override
  String get aiMaxTruncationContinuationsSaved =>
      'Limite de continuation automatique mise à jour.';

  @override
  String get aiMaxTruncationContinuationsInvalid =>
      'Saisissez un entier entre 0 et 100.';

  @override
  String get aiEstimatedCharactersPerTokenLabel =>
      'Ratio estimé caractères par jeton';

  @override
  String get aiEstimatedCharactersPerTokenBody =>
      'Caractères approximatifs par jeton, utilisés pour estimer le budget de contexte. Par défaut 4 ; plage 1–32.';

  @override
  String get aiEstimatedCharactersPerTokenSave => 'Enregistrer le ratio';

  @override
  String get aiEstimatedCharactersPerTokenSaved =>
      'Ratio estimé caractères par jeton mis à jour.';

  @override
  String get aiEstimatedCharactersPerTokenInvalid =>
      'Saisissez un entier entre 1 et 32.';

  @override
  String get aiImageSizeLimitBody =>
      'Lorsque l’utilisateur joint une image dépassant ce plafond, OpenHand la compresse automatiquement (qualité + résolution) avant l’envoi. Accepte des valeurs décimales en Mo ; plage 0,0625 Mo (64 Ko) à 64 Mo.';

  @override
  String get aiImageSizeLimitFieldLabel => 'Limite (Mo)';

  @override
  String get aiImageSizeLimitSave => 'Enregistrer la limite';

  @override
  String get aiImageSizeLimitSaved =>
      'Limite de taille de pièce jointe d’image mise à jour.';

  @override
  String get aiImageSizeLimitInvalid =>
      'Saisissez un nombre positif valide en Mo.';

  @override
  String get imageEditorAspectFree => 'Libre';

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
  String get imageEditorAspectCircle => 'Cercle';

  @override
  String get imageEditorFlipHorizontal => 'Retournement horizontal';

  @override
  String get imageEditorFlipVertical => 'Retournement vertical';

  @override
  String get imageEditorSaturationLabel => 'Saturation';

  @override
  String get imageEditorExposureLabel => 'Exposition';

  @override
  String get imageEditorHueLabel => 'Teinte';

  @override
  String get imageEditorVignetteLabel => 'Vignettage';

  @override
  String get imageEditorFineRotationLabel => 'Rotation fine (°)';

  @override
  String get imageEditorSaveToFile => 'Enregistrer dans un fichier';

  @override
  String get imageEditorCopyToClipboard => 'Copier dans le presse-papiers';

  @override
  String imageEditorSavedTo(String path) {
    return 'Enregistré : $path';
  }

  @override
  String imageEditorSaveFailed(String error) {
    return 'Échec de l’enregistrement : $error';
  }

  @override
  String get imageEditorClipboardCopiedBitmap =>
      'Image copiée dans le presse-papiers. Le chemin du fichier a également été copié en tant que texte.';

  @override
  String imageEditorClipboardCopiedPath(String path) {
    return 'Chemin du fichier image copié dans le presse-papiers : $path';
  }

  @override
  String get imageEditorApplyButton => 'Appliquer';

  @override
  String get imageEditorUndoButton => 'Annuler';

  @override
  String get imageEditorResetAllButton => 'Tout réinitialiser';

  @override
  String get imageEditorCompareHold => 'Maintenir pour comparer';

  @override
  String get imageEditorCompareRelease => 'Relâcher';

  @override
  String get imageEditorCompareOriginal => 'Original';

  @override
  String get imageEditorWatermarkColorLabel => 'Couleur du texte';

  @override
  String get imageEditorWatermarkColorHue => 'Teinte';

  @override
  String get imageEditorWatermarkColorSaturation => 'Saturation';

  @override
  String get imageEditorWatermarkColorLightness => 'Luminosité';

  @override
  String get imageEditorApplySuccess => 'Réglages appliqués';

  @override
  String get imageEditorProcessing => 'Traitement…';

  @override
  String get builtinToolTimeoutLabel => 'Délai d’expiration (secondes)';

  @override
  String builtinToolTimeoutHint(int seconds) {
    return 'Par défaut ${seconds}s';
  }

  @override
  String builtinToolTimeoutHelper(int seconds) {
    return 'Vide = par défaut ${seconds}s. Garde-fou d’exécution pour les outils sans effet de bord ; Task/Bash/écriture utilisent leurs propres limites.';
  }

  @override
  String get builtinToolRetryLabel =>
      'Réessayer en cas d’échec / délai dépassé';

  @override
  String get builtinToolRetryBody =>
      'Désactivé par défaut. Ne réessaie que les outils sans effet de bord lors de vrais résultats failed/timed_out ; jamais les arguments invalides, appels refusés, Task, commandes d’écriture, modifications de fichiers, processus en arrière-plan, changements de compétence ou écritures mémoire.';

  @override
  String builtinToolMaxRetriesLabel(int max) {
    return 'Tentatives max. (0–$max)';
  }

  @override
  String builtinToolMaxRetriesHelper(int max) {
    return 'Hors première tentative ; plafonné à $max';
  }

  @override
  String get builtinToolBackoffLabel => 'Base de recul des tentatives (ms)';

  @override
  String builtinToolBackoffHint(int ms) {
    return 'Par défaut ${ms}ms';
  }

  @override
  String builtinToolBackoffHelper(int max) {
    return 'Exponentiel : la nième tentative attend base × 2^(N-1) ms, plafonné à ${max}ms';
  }

  @override
  String selfLearningFlushIntervalLabel(int ms) {
    return 'Intervalle de vidage du flux : ${ms}ms';
  }

  @override
  String selfLearningFlushIntervalHelper(int min, int max) {
    return 'Intervalle de persistance de la sortie en flux de la carte d’auto-apprentissage ($min–${max}ms). Plus petit = plus en temps réel mais plus d’à-coups de mise en page ; plus grand = plus fluide mais latence par bloc plus élevée. Par défaut 600ms.';
  }

  @override
  String get tsmRenameThreadTitle => 'Renommer le fil';

  @override
  String get tsmRenameHint => 'Saisir un titre de fil';

  @override
  String get tsmRenameFailed => 'Échec du renommage';

  @override
  String get tsmDeleteThreadTitle => 'Supprimer le fil';

  @override
  String get tsmDeleteSelectedTitle => 'Supprimer les fils sélectionnés';

  @override
  String tsmDeleteSelectedConfirm(int count) {
    return '$count fil(s) et leurs messages seront supprimés définitivement. Cette action est irréversible.';
  }

  @override
  String tsmDeleteFailedCount(int count) {
    return 'Échec de la suppression de $count fil(s)';
  }

  @override
  String get tsmSessionMissing => 'Session introuvable ou supprimée';

  @override
  String get tsmExportSessionDataTitle => 'Exporter les données de session';

  @override
  String tsmExportingSession(String title) {
    return 'Exportation de « $title »…';
  }

  @override
  String get tsmExportComplete => 'Exportation terminée';

  @override
  String get tsmExportFailed => 'Échec de l\'exportation';

  @override
  String get tsmChooseExportFolder => 'Choisir le dossier d\'export';

  @override
  String get tsmBatchExportTitle => 'Exportation par lots';

  @override
  String tsmBatchExportSubtitle(int count) {
    return 'Exportation imminente de $count fils…';
  }

  @override
  String tsmBatchExportDone(int ok, int failed) {
    return 'Export par lots terminé : $ok réussis / $failed échoués';
  }

  @override
  String get tsmMenuPreview => 'Aperçu';

  @override
  String get tsmMenuRename => 'Renommer';

  @override
  String get tsmMenuExportSession => 'Exporter la session';

  @override
  String get tsmMenuPin => 'Épingler';

  @override
  String get tsmMenuUnpin => 'Détacher';

  @override
  String get tsmMenuArchive => 'Archiver';

  @override
  String get tsmMenuUnarchive => 'Désarchiver';

  @override
  String get tsmMenuDelete => 'Supprimer';

  @override
  String get tsmPinUpdateFailed => 'Échec de la mise à jour de l\'épinglage';

  @override
  String get tsmArchiveUpdateFailed =>
      'Échec de la mise à jour de l\'archivage';

  @override
  String get tsmUntitledThread => '(Fil sans titre)';

  @override
  String tsmPreviewMessageCount(int count) {
    return '$count messages';
  }

  @override
  String get tsmClosePreview => 'Fermer l\'aperçu';

  @override
  String get tsmNoMessages => 'Aucun message';

  @override
  String get tsmEmptyMessage => '(vide)';

  @override
  String get tsmSearchHint => 'Rechercher par titre ou ID';

  @override
  String get tsmDensityComfortable => 'Confortable';

  @override
  String get tsmDensityCompact => 'Compact';

  @override
  String get tsmAllTemplates => 'Tous les modèles';

  @override
  String tsmSortDisabledHint(String mode) {
    return 'Trié par « $mode ». Les poignées sont désactivées ; revenez à « Ordre manuel » pour réorganiser.';
  }

  @override
  String get tsmSortManual => 'Ordre manuel';

  @override
  String get tsmSortUpdated => 'Récemment mis à jour';

  @override
  String get tsmSortCreated => 'Récemment créés';

  @override
  String get tsmSortSize => 'Par taille';

  @override
  String get tsmSortMessages => 'Par messages';

  @override
  String get tsmSortToken => 'Par tokens';

  @override
  String get tsmHideArchived => 'Masquer les archives';

  @override
  String get tsmShowArchived => 'Afficher les archives';

  @override
  String get tsmExitSelection => 'Quitter la sélection';

  @override
  String get tsmEnterSelection => 'Sélection multiple';

  @override
  String get tsmClose => 'Fermer';

  @override
  String get tsmTitle => 'Gestion des sessions de fil';

  @override
  String tsmHeaderSubtitle(int count) {
    return '$count fil(s) · maintenez ou glissez la poignée pour réorganiser, double-clic / clic droit pour plus d\'options';
  }

  @override
  String tsmSelectedCount(int count) {
    return '$count sélectionné(s)';
  }

  @override
  String get tsmBatchExportButton => 'Exporter par lots';

  @override
  String get tsmDeleteSelectedButton => 'Supprimer la sélection';

  @override
  String get tsmEmptyState => 'Aucune session de fil pour le moment';

  @override
  String get tsmCancel => 'Annuler';

  @override
  String get settingsThreadSessionManagementTitle =>
      'Gestion des sessions de fil';

  @override
  String get settingsThreadSessionManagementSubtitle =>
      'Inspectez le titre, l\'heure de création et de mise à jour, l\'empreinte de stockage, la composition des messages et les statistiques de tokens de chaque fil. Prend en charge le glisser-déposer pour réorganiser, la suppression par sélection multiple, ainsi qu\'un menu en double-clic ou clic droit pour renommer, exporter ou supprimer. L\'animation d\'entrée et de sortie de la boîte de dialogue suit la configuration globale d\'animation des dialogues.';

  @override
  String get settingsThreadSessionManagementOpen => 'Ouvrir le gestionnaire';

  @override
  String get settingsMessageGatewayTitle => 'Passerelle de messages';

  @override
  String get settingsMessageGatewayDescription =>
      'Configurez la plateforme Web générale de messages intégrée : écoute, authentification, sessions, chat Web, contrôles de santé, journaux et opérations.';

  @override
  String get tsmRowUnknown => 'inconnu';

  @override
  String get tsmRowCreated => 'Créé';

  @override
  String get tsmRowUpdated => 'Mis à jour';

  @override
  String get tsmRowSize => 'Taille';

  @override
  String get tsmRowMessages => 'Messages';

  @override
  String get tsmRowToken => 'Jeton';

  @override
  String get tsmRowByKind => 'Répartition';

  @override
  String get inputRepairTitle => 'Réparation de saisie';

  @override
  String get inputRepairBody =>
      'Récupère les processus enfants orphelins (osascript, LSP, MCP, …) et réinitialise le contexte de saisie macOS — corrige les TextField globaux qui refusent la saisie, le copier/coller ou ESC.';

  @override
  String get inputRepairButton => 'Réparer la saisie';

  @override
  String get inputRepairDone => 'Contexte de saisie réinitialisé.';

  @override
  String inputRepairDoneDetail(int count) {
    return 'Contexte de saisie réinitialisé ; $count processus enfants récupérés.';
  }

  @override
  String get proxySectionTitle => 'Système';

  @override
  String get proxySectionBody =>
      'Tous les clients HTTP internes (WebSearch / WebFetch, etc.) utilisent le proxy défini ici. Les modifications sont appliquées immédiatement, sans redémarrage.';

  @override
  String get proxyModeLabel => 'Mode proxy';

  @override
  String get proxyModeBody =>
      'Détermine la façon dont les clients HTTP internes (WebSearch / WebFetch, etc.) choisissent un proxy.';

  @override
  String get proxyModeDisabled => 'Sans proxy';

  @override
  String get proxyModeAutomatic => 'Détection automatique (par défaut)';

  @override
  String get proxyModeManual => 'Manuel';

  @override
  String get proxyProtocolsLabel => 'Protocoles';

  @override
  String get proxyProtocolsBody =>
      'Sélection multiple. Au moins un doit rester ; tout vider rétablit HTTP + HTTPS.';

  @override
  String get proxyHostLabel => 'Serveur (IP ou nom d’hôte)';

  @override
  String get proxyPortLabel => 'Port';

  @override
  String get proxyAuthLabel => 'Activer l’authentification du proxy';

  @override
  String get proxyAuthBody =>
      'Le nom d’utilisateur / mot de passe ne servent que si activé (HTTP Basic).';

  @override
  String get proxyUsernameLabel => 'Nom d’utilisateur';

  @override
  String get proxyPasswordLabel => 'Mot de passe';

  @override
  String get proxyExceptionsLabel =>
      'Ignorer le proxy pour ces hôtes et domaines';

  @override
  String get proxyExceptionsBody =>
      'Une entrée par ligne. Prend en charge : IP (127.0.0.1), CIDR IPv4 (192.168.0.0/16), domaine (example.com inclut les sous-domaines), glob (*.example.com) et regex (/^api\\d+\\.example\\.com\$/i). localhost / 127.0.0.1 / ::1 toujours directs.';

  @override
  String get proxyExceptionsHint =>
      'ex.\n*.local\n10.0.0.0/8\n/^api\\d+\\.example\\.com\$/i';

  @override
  String get proxyTestButton => 'Tester la connectivité du proxy';

  @override
  String get proxyTesting => 'Test en cours…';

  @override
  String proxyTestSuccess(int latency, String via) {
    return 'OK ($latency ms, via $via)';
  }

  @override
  String proxyTestFailure(String reason) {
    return 'Échec : $reason';
  }

  @override
  String get proxyTestEndpointLabel => 'URL de test';

  @override
  String get proxyTestEndpointHint =>
      'Par défaut : https://www.google.com/generate_204';

  @override
  String get proxyTestVerdictDirect => 'directe';

  @override
  String proxyTestVerdictProxy(String endpoint) {
    return 'proxy $endpoint';
  }

  @override
  String get proxyTestEndpointInvalid =>
      'L\'URL de test est invalide (doit commencer par http:// ou https://)';

  @override
  String get proxyTestConsoleTitle => 'Diagnostic de connectivité du proxy';

  @override
  String get proxyTestConsoleRunning => 'Sondage en cours…';

  @override
  String get proxyTestConsoleSucceeded => 'Terminé : route saine';

  @override
  String get proxyTestConsoleFailed => 'Terminé : problèmes détectés';

  @override
  String get proxyTestConsoleCopy => 'Copier le journal';

  @override
  String get proxyTestConsoleCopied => 'Journal copié dans le presse-papiers';

  @override
  String get proxyTestConsoleClose => 'Fermer';

  @override
  String get proxyTestConsoleRerun => 'Relancer';

  @override
  String get proxyTestConsoleMaximize => 'Agrandir';

  @override
  String get proxyTestConsoleRestore => 'Restaurer';

  @override
  String get proxyTestConsoleClear => 'Effacer la console';

  @override
  String get tokenPopupCostHeading => 'Coût';

  @override
  String get tokenPopupCostInput => 'Entrée';

  @override
  String get tokenPopupCostOutput => 'Sortie';

  @override
  String get tokenPopupCostCacheRead => 'Lecture du cache';

  @override
  String get tokenPopupCostCacheWrite => 'Écriture du cache';

  @override
  String get tokenPopupCostTotal => 'Total';

  @override
  String get tokenDialUnit => 'Jeton';

  @override
  String get tokenPopupInputHeading => 'Entrée';

  @override
  String get tokenPopupPrompt => 'Invite';

  @override
  String get tokenPopupAudioInput => 'Entrée audio';

  @override
  String get tokenPopupImageInput => 'Entrée image';

  @override
  String get tokenPopupVideoInput => 'Entrée vidéo';

  @override
  String get tokenPopupCacheRead => 'Lecture du cache';

  @override
  String get tokenPopupCacheWrite => 'Écriture du cache';

  @override
  String get tokenPopupOutputHeading => 'Sortie';

  @override
  String get tokenPopupCompletion => 'Réponse';

  @override
  String get tokenPopupReasoning => 'Raisonnement';

  @override
  String get tokenPopupWebSearchHeading => 'Recherche web';

  @override
  String get tokenPopupWebSearchCalls => 'Appels';

  @override
  String get tokenPopupWebSearchPages => 'Pages';

  @override
  String get tokenPopupGrandTotal => 'Total général';

  @override
  String get tokenPopupContextOverview => 'Vue d’ensemble du contexte';

  @override
  String get tokenPopupContextMeasured => 'Total mesuré · catégories réparties';

  @override
  String get tokenPopupContextEstimated =>
      'Estimé selon le contenu de la requête';

  @override
  String get tokenPopupContextEmpty =>
      'Envoyez le prochain message pour générer cette vue';

  @override
  String get tokenPopupContextSystemPrompt => 'Prompt système';

  @override
  String get tokenPopupContextBuiltinTools => 'Outils intégrés';

  @override
  String get tokenPopupContextMcp => 'MCP';

  @override
  String get tokenPopupContextInstructions => 'Instructions';

  @override
  String get tokenPopupContextMemory => 'Mémoire';

  @override
  String get tokenPopupContextSkills => 'Compétences';

  @override
  String get tokenPopupContextHooks => 'Hooks';

  @override
  String get tokenPopupContextConversation => 'Conversation';

  @override
  String get tokenPopupContextRuntime => 'Exécution';

  @override
  String get tokenPopupContextWindow => 'Fenêtre de contexte';

  @override
  String get tokenPopupCompactNow => 'Compresser';

  @override
  String get tokenPopupCompacting => 'Compression…';

  @override
  String get tokenPopupSessionHeading => 'Session';

  @override
  String get tokenPopupMessages => 'Messages';

  @override
  String get tokenPopupPromptBuilds => 'Constructions d\'invite';

  @override
  String get tokenPopupPromptChars => 'Caractères d\'invite';

  @override
  String get tokenPopupCacheHitModeExcludeExpired => 'Sans anomalies expirées';

  @override
  String get tokenPopupCacheHitModeIncludeExpired => 'Avec anomalies expirées';

  @override
  String tokenPopupExcludedRounds(int count) {
    return '$count exclues';
  }

  @override
  String get tokenPopupPrefixReuse => 'Réutilisation du préfixe';

  @override
  String tokenPopupTooltipFreshReuse(String fresh, int reuse) {
    return '+$fresh nouveaux · réutil. $reuse%';
  }

  @override
  String get tokenPopupFirstRequestShort => 'Première ignorée';

  @override
  String get tokenPopupFirstRequestNotAveraged => 'Hors moyenne';

  @override
  String get tokenPopupTrendNoData =>
      'Aucune donnée de taux de cache pour l\'instant. La tendance apparaîtra après l\'envoi de messages.';

  @override
  String get tokenPopupTrendOnlyFirstIgnored =>
      'La première requête est ignorée. La tendance démarre après la prochaine requête normale.';

  @override
  String get tokenPopupTrendFirstReferenceOnly =>
      'La première requête sert seulement de référence et n\'est pas incluse dans la moyenne.';

  @override
  String get tokenPopupUncached => 'Non mis en cache';

  @override
  String get toolbarSessionMetadata => 'Métadonnées de session';

  @override
  String get toolbarShowPlan => 'Afficher le plan';

  @override
  String get toolbarHidePlan => 'Masquer le plan';

  @override
  String get toolbarPlanAwaitingApproval => 'Plan en attente';

  @override
  String get toolbarPlanNeedsReview => 'Plan à revoir';

  @override
  String get toolbarPlanNeedsAttention => 'Plan à traiter';

  @override
  String get toolbarPlanCompleted => 'Plan terminé';

  @override
  String get toolbarPlanInProgress => 'Plan en cours';

  @override
  String get toolbarPlanConfirmToBegin => 'Confirmer pour démarrer';

  @override
  String get toolbarPlanInspectBeforeResume =>
      'Vérifier les étapes, artefacts et todos avant de reprendre';

  @override
  String get toolbarPlanStepFailed =>
      'Une étape a échoué. Vérifiez puis continuez.';

  @override
  String get toolbarPlanPending => 'En attente';

  @override
  String get toolbarPlanReview => 'À revoir';

  @override
  String get toolbarToolsProtocolUnsupported =>
      'Le protocole du modèle ne prend pas en charge les outils';

  @override
  String get toolbarRuntimeNoSnapshot => 'Aucun instantané d\'outils runtime';

  @override
  String get toolbarToolsCatalogStale =>
      'Le catalogue est obsolète, mise à jour prochaine';

  @override
  String get toolbarRuntimeCatalogSynced =>
      'Catalogue d\'outils runtime synchronisé';

  @override
  String get toolbarPlanAwaitingNoExecTools =>
      'Plan en attente, outils d\'exécution masqués';

  @override
  String get toolbarPlanReviewBeforeResume =>
      'Vérifier étapes, artefacts et todos';

  @override
  String get toolbarPlanApprovedExecOpen =>
      'Plan approuvé, outils d\'exécution disponibles';

  @override
  String get toolbarPlanOnlyPlanningExitAllowed =>
      'Outils de planification uniquement, jusqu\'à plan prêt';

  @override
  String get toolbarPlanOnlyPlanningOnly =>
      'Outils de planification uniquement';

  @override
  String get toolbarModeJustSwitched =>
      'Mode changé, catalogue mis à jour à la prochaine ronde';

  @override
  String get toolbarChatModeNoTools =>
      'Aucun outil disponible en mode discussion';

  @override
  String get toolbarChatModeAllTools =>
      'Mode discussion expose le catalogue complet';

  @override
  String get toolbarRuntimeNoSnapshotPrompt =>
      'Aucun instantané runtime, envoyez d\'abord une requête';

  @override
  String get toolbarGateNoReason => 'Aucune raison de blocage';

  @override
  String get toolbarGateProtocolUnsupportedSwitchPlan =>
      'Protocole sans support outils. Cliquer pour passer en mode plan.';

  @override
  String get toolbarGateChatActiveSwitchPlan =>
      'Mode discussion actif. Cliquer pour passer en mode plan.';

  @override
  String get toolbarGatePlanActiveSwitchChat =>
      'Mode plan actif. Cliquer pour discussion.';

  @override
  String get toolbarGateProtocolUnsupportedSwitchChat =>
      'Protocole sans support outils. Mode plan peut structurer les étapes mais pas exécuter. Cliquer pour discussion.';

  @override
  String get toolbarGatePlanJustSwitchedToChat =>
      'Mode plan changé. Outils mis à jour à la prochaine ronde. Cliquer pour discussion.';

  @override
  String get toolbarGatePlanAwaitingSwitchChat =>
      'Plan en attente. Outils masqués jusqu\'à approbation. Cliquer pour discussion.';

  @override
  String get toolbarGatePlanReviewSwitchChat =>
      'Plan à revoir. Vérifier étapes, artefacts et todos avant de continuer. Cliquer pour discussion.';

  @override
  String get toolbarGatePlanExecutingSwitchChat =>
      'Plan en exécution. Outils selon catalogue. Cliquer pour discussion.';

  @override
  String get toolbarGatePlanModeSwitchChat =>
      'Mode plan actif. Planifie puis exécute après approbation. Cliquer pour discussion.';

  @override
  String get toolbarFilesShow => 'Fichiers projet';

  @override
  String get toolbarFilesHide => 'Masquer fichiers';

  @override
  String get toolbarRuntimeModeChat => 'Mode discussion';

  @override
  String get toolbarRuntimeModeChatCompact => 'Discussion';

  @override
  String get toolbarRuntimeModePlan => 'Mode plan';

  @override
  String get toolbarRuntimeModePlanCompact => 'Plan';

  @override
  String get toolbarRuntimeModePlanAwaiting => 'Plan en attente';

  @override
  String get toolbarRuntimeModePlanAwaitingCompact => 'En attente';

  @override
  String get toolbarRuntimeModePlanReview => 'Plan à revoir';

  @override
  String get toolbarRuntimeModePlanReviewCompact => 'À revoir';

  @override
  String get toolbarRuntimeModePlanExecution => 'Exécution';

  @override
  String get toolbarRuntimeModePlanExecutionCompact => 'Exécuter';

  @override
  String get toolbarRuntimeModePlanDrafting => 'Plan en préparation';

  @override
  String get toolbarRuntimeModePlanDraftCompact => 'Brouillon';

  @override
  String toolbarRuntimeNotices(int count) {
    return '$count notices runtime';
  }

  @override
  String toolbarMcpLazyLoading(int loaded, int total) {
    return 'MCP $loaded/$total chargés';
  }

  @override
  String snackToolSearchLoaded(int loaded, int total) {
    return 'ToolSearch a chargé $loaded/$total outil(s) MCP';
  }

  @override
  String get snackToolSearchLoadedAction => 'Voir la liste';

  @override
  String get snackToolSearchLoadedDialogTitle =>
      'Outils MCP chargés par ToolSearch';

  @override
  String get snackToolSearchLoadedDialogClose => 'Fermer';

  @override
  String get snackToolSearchLoadedCopyAction => 'Copier select:';

  @override
  String get snackToolSearchLoadedCopiedToast => 'Copié';

  @override
  String get snackToolSearchLoadedClearAction => 'Vider la liste chargée';

  @override
  String get snackToolSearchLoadedClearedToast => 'Liste chargée vidée';

  @override
  String get snackToolSearchLoadedGroupOther => 'Autre (sans préfixe serveur)';

  @override
  String get snackToolSearchLoadedCopyGroupAction => 'Copier tout le groupe';

  @override
  String get snackToolSearchLoadedTabLoaded => 'Chargés';

  @override
  String get snackToolSearchLoadedTabHistory => 'Historique';

  @override
  String get snackToolSearchLoadedHistoryEmpty =>
      'Aucun chargement ToolSearch dans cette session';

  @override
  String get snackToolSearchLoadedHistoryQueryPrefix => 'Requête : ';

  @override
  String get snackToolSearchLoadedFilterHint => 'Filtrer par nom…';

  @override
  String get snackToolSearchLoadedHistoryFilterHint =>
      'Filtrer par nom ou requête…';

  @override
  String get snackToolSearchLoadedSourceAi => 'Session IA';

  @override
  String get snackToolSearchLoadedSourceHarness => 'Phase Harness';

  @override
  String get snackToolSearchLoadedReplayedToast =>
      'ToolSearch relancé avec la sélection précédente';

  @override
  String get snackToolSearchLoadedReplayPendingToast =>
      'Envoi imminent — appuyez sur Annuler pour interrompre';

  @override
  String get snackToolSearchLoadedReplayCancelAction => 'Annuler';

  @override
  String get snackToolSearchLoadedReplayCancelledToast =>
      'Envoi annulé — composer vidé';

  @override
  String get snackToolSearchLoadedSourceFilterAll => 'Tous';

  @override
  String get snackToolSearchLoadedSourceFilterAi => 'IA seulement';

  @override
  String get snackToolSearchLoadedSourceFilterHarness => 'Harness uniquement';

  @override
  String snackToolSearchLoadedSummary(int queries, int tools) {
    return '$tools outil(s) MCP chargé(s) depuis $queries requête(s) dans cette session';
  }

  @override
  String get snackToolSearchLoadedHistoryReplayAction =>
      'Copier ce lot en tant que select:…';

  @override
  String get snackToolSearchLoadedHistoryClearAction => 'Effacer l\'historique';

  @override
  String get snackToolSearchLoadedHistoryExportTooltip =>
      'Exporter l’historique';

  @override
  String get snackToolSearchLoadedHistoryExportCsv => 'Copier en CSV';

  @override
  String get snackToolSearchLoadedHistoryExportMarkdown => 'Copier en Markdown';

  @override
  String get snackToolSearchLoadedHistoryExportJson => 'Copier en JSON';

  @override
  String get snackToolSearchLoadedHistoryExportSaveCsv => 'Enregistrer en CSV…';

  @override
  String get snackToolSearchLoadedHistoryExportSaveMarkdown =>
      'Enregistrer en Markdown…';

  @override
  String get snackToolSearchLoadedHistoryExportSaveJson =>
      'Enregistrer en JSON…';

  @override
  String get snackToolSearchLoadedHistoryExportCsvHint =>
      'Idéal pour les tableurs : une ligne par requête.';

  @override
  String get snackToolSearchLoadedHistoryExportMarkdownHint =>
      'Tableau GitHub : parfait pour les issues et la doc.';

  @override
  String get snackToolSearchLoadedHistoryExportJsonHint =>
      'Charge utile structurée : ré-importable dans OpenHand.';

  @override
  String get toolSearchLoadedHistoryImportTooltip => 'Importer un export JSON';

  @override
  String get toolSearchLoadedHistoryImportDialogTitle =>
      'Aperçu de l’import d’historique ToolSearch';

  @override
  String toolSearchLoadedHistoryImportDialogCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées',
      one: '1 entrée',
      zero: 'aucune entrée',
    );
    return '$_temp0';
  }

  @override
  String get toolSearchLoadedHistoryImportDialogEmpty =>
      'Aucune entrée trouvée dans le fichier.';

  @override
  String get toolSearchLoadedHistoryImportDialogClose => 'Fermer';

  @override
  String snackToolSearchLoadedHistoryExportSavedToast(int count, String path) {
    return '$count entrées enregistrées dans $path';
  }

  @override
  String snackToolSearchLoadedHistoryExportSaveFailedToast(String error) {
    return 'Échec de l’enregistrement : $error';
  }

  @override
  String get snackToolSearchLoadedHistoryExportRevealAction => 'Révéler';

  @override
  String get snackToolSearchLoadedHistoryExportEmptyToast =>
      'Historique vide après filtrage ; rien à exporter.';

  @override
  String snackToolSearchLoadedHistoryExportedToast(int count) {
    return '$count entrées d’historique copiées dans le presse-papiers.';
  }

  @override
  String get snackToolSearchLoadedHistoryClearedToast =>
      'Historique de chargement effacé';

  @override
  String get mcpLazyLoadingViewLoadedAction =>
      'Voir la liste chargée (session actuelle)';

  @override
  String get mcpToolSearchExportLastDirResetAction =>
      'Réinitialiser le dossier d’export mémorisé';

  @override
  String get mcpToolSearchExportLastDirResetToast =>
      'Dossier d’export mémorisé effacé';

  @override
  String get mcpLazyLoadingNoActiveSession => 'Aucune session active';

  @override
  String toolbarPlanStepsCompleted(int completed, int total) {
    return '$completed/$total étapes terminées';
  }

  @override
  String get mdlEdEnterAValidBaseUrlFirst =>
      'Saisissez d’abord une URL de base valide';

  @override
  String get mdlEdNoModelsFoundFromThisProvider =>
      'Aucun modèle trouvé chez ce fournisseur.';

  @override
  String get mdlEdProviderName => 'Nom du fournisseur';

  @override
  String get mdlEdOptionalEGDeepseekLocalOllama =>
      'Optionnel, par ex. DeepSeek, Ollama local';

  @override
  String get mdlEdCurrentlyActiveModel => 'Modèle actuellement actif';

  @override
  String get mdlEdClickToSetAsActiveModel =>
      'Cliquez pour définir comme modèle actif';

  @override
  String get mdlEdTapScanModelsToDiscoverModels =>
      'Appuyez sur « Analyser les modèles » pour les découvrir automatiquement, ou ajoutez-les manuellement ci-dessous.';

  @override
  String get mdlEdActiveModelId => 'ID du modèle actif';

  @override
  String get mdlEdTheModelUsedForConversationsSelect =>
      'Le modèle utilisé pour les conversations. Sélectionnez-le dans la liste ci-dessus ou saisissez-le directement.';

  @override
  String get mdlEdMaxContextTokens => 'Jetons de contexte max.';

  @override
  String get mdlEdOptionalLimitsTheHistorySliceUsed =>
      'Optionnel. Limite la portion d’historique utilisée pendant la compression.';

  @override
  String get mdlEdEnterAWholeNumberGreaterThan =>
      'Saisissez un nombre entier supérieur à 0';

  @override
  String get mdlEdRequestMethod => 'Méthode de requête';

  @override
  String get mdlEdOutputMode => 'Mode de sortie';

  @override
  String get mdlEdStreaming => 'Diffusion';

  @override
  String get mdlEdNonStreaming => 'Sans flux';

  @override
  String get mdlEdMaxOutputTokens => 'Jetons de sortie max.';

  @override
  String get mdlEdOptionalUsesAdapterDefaultIfUnset =>
      'Optionnel. Utilise la valeur par défaut de l’adaptateur si non défini.';

  @override
  String get mdlEdTemperature => 'Température';

  @override
  String get mdlEd0020Default0 => '0,0 ~ 2,0, par défaut 0,7';

  @override
  String get mdlEdEnterANumberBetween00 =>
      'Saisissez un nombre entre 0,0 et 2,0';

  @override
  String get mdlEdCustomHeaders => 'En-têtes personnalisés';

  @override
  String get mdlEdAdd => 'Ajouter';

  @override
  String get mdlEdNoCustomHeadersTapAddTo =>
      'Aucun en-tête personnalisé. Appuyez sur « Ajouter » pour en créer un.';

  @override
  String get mdlEdHeaderName => 'Nom de l’en-tête';

  @override
  String get mdlEdHeaderValue => 'Valeur de l’en-tête';

  @override
  String get mdlEdEditModelProfile => 'Modifier le profil du modèle';

  @override
  String get mdlEdDisplayName => 'Nom affiché';

  @override
  String get mdlEdOptionalShownInTheUi => 'Optionnel, affiché dans l’interface';

  @override
  String get mdlEdDescription => 'Description';

  @override
  String get mdlEdMultimodalSupport => 'Prise en charge multimodale';

  @override
  String get mdlEdAutoDetect => 'Détection automatique';

  @override
  String get mdlEdYes => 'Oui';

  @override
  String get mdlEdNo => 'Non';

  @override
  String get mdlEdSupportsAttachments => 'Prend en charge les pièces jointes';

  @override
  String get mdlEdReasoningEcho => 'Inclure l\'historique de raisonnement';

  @override
  String get mdlEdReasoningEchoHint =>
      'Détermine si le contenu de réflexion/raisonnement des tours précédents est réinjecté dans l\'historique du prompt pour ce modèle.';

  @override
  String get mdlEdSupportedModalities => 'Modalités prises en charge';

  @override
  String get mdlEdText => 'Texte';

  @override
  String get mdlEdImage => 'Image';

  @override
  String get mdlEdVideo => 'Vidéo';

  @override
  String get mdlEdAudio => 'Audio';

  @override
  String get mdlEdGenerationCapabilities => 'Capacités de génération';

  @override
  String get mdlEdPdf => 'PDF';

  @override
  String get mdlEdPpt => 'PPT';

  @override
  String get mdlEdTokenLimits => 'Limites de jetons';

  @override
  String get mdlEdContextLength => 'Longueur du contexte';

  @override
  String get mdlEdSummaryLength => 'Longueur du résumé';

  @override
  String get mdlEdOutputLength => 'Longueur de la sortie';

  @override
  String get mdlEdThinkingLength => 'Longueur de réflexion';

  @override
  String get mdlEdTokenPricingUsd1mTokensLeave =>
      'Tarification des jetons (USD / 1M jetons, laisser vide si non défini)';

  @override
  String get mdlEdInput => 'Entrée';

  @override
  String get mdlEdOutput => 'Sortie';

  @override
  String get mdlEdCacheRead => 'Lecture cache';

  @override
  String get mdlEdCacheWrite => 'Écriture cache';

  @override
  String get mdlEdReset => 'Réinitialiser';

  @override
  String get mdlEdCancel => 'Annuler';

  @override
  String get mdlEdOk => 'OK';

  @override
  String get tlCallDir => 'Dossier';

  @override
  String get tlCallElapsed => 'Écoulé';

  @override
  String get tlCallExit => 'Sortie';

  @override
  String get tlCallToolInput => 'Entrée de l’outil';

  @override
  String get tlCallCommand => 'commande';

  @override
  String get tlCallArguments => 'arguments';

  @override
  String get tlCallToolOutput => 'Sortie de l’outil';

  @override
  String get tlCallNoOutputYet => 'Aucune sortie pour l’instant';

  @override
  String get tlCallResult => 'résultat';

  @override
  String get tlCallStdout => 'stdout';

  @override
  String get tlCallStderr => 'stderr';

  @override
  String get tlCallArgumentsConstructing => 'Construction des arguments…';

  @override
  String get tlCallArgumentsConstructingHint =>
      'Les arguments sont toujours en cours de réception ; la carte basculera à l’état normal une fois la construction terminée.';

  @override
  String get tlCallCollectedParameters => 'Collectés';

  @override
  String get tlCallNoParametersYet => 'Aucun argument analysé';

  @override
  String get tlCallSubmitting => 'Envoi en cours…';

  @override
  String get tlCallSubmittingHint =>
      'Paramètres capturés ; transfert à l’exécuteur';

  @override
  String get tlCallThereIsNoToolOutputYet =>
      'Aucune sortie d’outil pour l’instant.';

  @override
  String get tlCallViewInDialog => 'Afficher dans la boîte de dialogue';

  @override
  String get tlCallEmptyContent => 'Contenu vide';

  @override
  String get fileMutationSection => 'Modifications de fichiers';

  @override
  String fileMutationFilesChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers modifiés',
      one: '1 fichier modifié',
    );
    return '$_temp0';
  }

  @override
  String fileMutationFilesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers',
      one: '1 fichier',
    );
    return '$_temp0';
  }

  @override
  String get fileMutationUndoAll => 'Tout annuler';

  @override
  String get fileMutationRefresh => 'Actualiser';

  @override
  String get fileMutationCopyAllDiff => 'Copier tous les diffs';

  @override
  String get fileMutationCopyAllDiffDone =>
      'Tous les diffs copiés dans le presse-papiers';

  @override
  String get fileMutationRevealLedger =>
      'Afficher ledger.jsonl dans le gestionnaire de fichiers';

  @override
  String get fileMutationCopyPath => 'Copier le chemin du fichier';

  @override
  String get fileMutationPathCopied => 'Chemin copié';

  @override
  String fileMutationRevealMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'modifications masquées',
      one: 'modification masquée',
    );
    return '$count $_temp0 — appuyez pour afficher le lot suivant';
  }

  @override
  String get fileMutationRevealAll => 'Tout afficher';

  @override
  String get fileMutationHistoryInspector => 'Inspecteur d\'historique';

  @override
  String get fileMutationHistoryInspectorTitle =>
      'Historique des fichiers de la session';

  @override
  String get fileMutationHistoryInspectorFilterHint => 'Filtrer par chemin…';

  @override
  String get fileMutationHistoryInspectorEmpty =>
      'Aucune modification de fichier ne correspond au filtre.';

  @override
  String get fileMutationHistoryInspectorZoomIn => 'Cibler ce chemin';

  @override
  String get fileMutationHistoryInspectorZoomOut => 'Afficher tous les chemins';

  @override
  String get fileMutationUndone => 'Annulé';

  @override
  String get fileMutationCascadeUndone => 'Annulation en cascade';

  @override
  String get fileMutationUndoThis => 'Annuler cette modification';

  @override
  String get fileMutationRedo => 'Rétablir';

  @override
  String get fileMutationUndoFailed => 'Échec de l\'annulation';

  @override
  String get fileMutationRedoFailed => 'Échec du rétablissement';

  @override
  String get fileMutationSnapshotUnavailable =>
      'Instantané du contenu indisponible';

  @override
  String get tlCallTool => 'Outil';

  @override
  String get tlCallSkill => 'Compétence';

  @override
  String get tlCallStopped => 'Arrêté';

  @override
  String get tlCallStopRequest => 'Arrêter cet appel d\'outil';

  @override
  String get tlCallBlocked => 'Bloqué';

  @override
  String get tlCallRejected => 'Refusé';

  @override
  String get tlCallInvalid => 'Invalide';

  @override
  String get tlCallToolCall => 'Appel d’outil';

  @override
  String get tlCallRunning => 'En cours';

  @override
  String get tlCallSucceeded => 'Réussi';

  @override
  String get tlCallDenied => 'Refusé';

  @override
  String get tlCallTimedOut => 'Délai dépassé';

  @override
  String get tlCallFailed => 'Échec';

  @override
  String get tlCallToolIsRunningWaitingForOutput =>
      'Outil en cours d’exécution. En attente de la sortie…';

  @override
  String get tlCallExpandToInspectToolOutput =>
      'Développez pour inspecter la sortie de l’outil';

  @override
  String get tlCallSelfLearning => 'Auto-apprentissage';

  @override
  String get tlCallNudgeRecovered => 'Récupéré par incitation';

  @override
  String get tlCallProfileChanges => 'Modifications du profil';

  @override
  String get tlCallMemoryChanges => 'Modifications de la mémoire';

  @override
  String get tlCallSkillChanges => 'Modifications de compétences';

  @override
  String get tlCallProfileDiff => 'Diff de profil';

  @override
  String get tlCallNoChanges => 'Aucune modification';

  @override
  String get tlCallUnnamed => '(sans nom)';

  @override
  String get tlCallJustNow => 'à l’instant';

  @override
  String get sessMetaCacheHitTrend => 'TENDANCE DU TAUX DE SUCCÈS DU CACHE';

  @override
  String get sessMetaCacheHitLast => 'dernier';

  @override
  String get sessMetaCacheHitAvg => 'moyenne';

  @override
  String get sessMetaCacheHitMax => 'max';

  @override
  String get sessMetaCacheHitOverlayOn => 'Superposer l\'autre formule';

  @override
  String get sessMetaCacheHitOverlayOff => 'Masquer la superposition';

  @override
  String get sessMetaCacheHitFormulaClaude => 'Formule Claude';

  @override
  String get sessMetaCacheHitFormulaOpenAi => 'Formule OpenAI';

  @override
  String sessMetaCacheHitPoint(int index) {
    return 'Tour $index';
  }

  @override
  String get sessMetaMessages => 'Messages';

  @override
  String get sessMetaPromptBuilds => 'Constructions de prompt';

  @override
  String get sessMetaCompressions => 'Compressions';

  @override
  String get sessMetaTotalTokens => 'Jetons totaux';

  @override
  String get sessMetaMode => 'Mode';

  @override
  String get sessMetaRuntimeTools => 'Outils d’exécution';

  @override
  String get sessMetaPending => 'En attente';

  @override
  String get sessMetaCurrentSessionMetadata =>
      'Métadonnées de la session actuelle';

  @override
  String get sessMetaSessionOverview => 'Aperçu de la session';

  @override
  String get sessMetaExtendedMetadata => 'Métadonnées étendues';

  @override
  String get sessMetaStatistics => 'Statistiques';

  @override
  String get sessMetaUser => 'Utilisateur';

  @override
  String get sessMetaAssistant => 'Assistant';

  @override
  String get sessMetaTool => 'Outil';

  @override
  String get sessMetaSkill => 'Compétence';

  @override
  String get sessMetaCompression => 'Compression';

  @override
  String get sessMetaEnvironment => 'Environnement';

  @override
  String get sessMetaCommandPolicy => 'Politique de commande';

  @override
  String get sessMetaPromptMetadataIsNotAvailableYet =>
      'Les métadonnées de prompt ne sont pas encore disponibles.';

  @override
  String get sessMetaWriteConfirmation => 'Confirmation d’écriture';

  @override
  String get sessMetaRequired => 'Requis';

  @override
  String get sessMetaNotRequired => 'Non requis';

  @override
  String get sessMetaAllowRules => 'Règles d’autorisation';

  @override
  String get sessMetaThereAreNoSurfacedAllowCommand =>
      'Aucune règle d’autorisation de commande visible.';

  @override
  String get sessMetaRuntimeOrchestration => 'Orchestration d’exécution';

  @override
  String get sessMetaStateSource => 'Source de l’état';

  @override
  String get sessMetaGeneratedFromTheCurrentModelMcp =>
      'Généré à partir du modèle actuel, MCP/compétences et état du plan';

  @override
  String get sessMetaTheLastPersistedRuntimeSnapshot =>
      'Le dernier instantané d’exécution persisté';

  @override
  String get sessMetaToolCatalogState => 'État du catalogue d’outils';

  @override
  String get sessMetaGateReason => 'Raison du verrou';

  @override
  String get sessMetaRuntimeToolCount => 'Nombre d’outils d’exécution';

  @override
  String get sessMetaRefreshesNextRound => 'Se rafraîchit au prochain tour';

  @override
  String get sessMetaRuntimeNotices => 'Avis d’exécution';

  @override
  String get sessMetaCurrentRuntimeTools => 'Outils d’exécution actuels';

  @override
  String get sessMetaTaskTracking => 'Suivi des tâches';

  @override
  String get sessMetaCurrentTodos => 'Tâches actuelles';

  @override
  String get sessMetaPlanRecords => 'Enregistrements de plan';

  @override
  String get sessMetaTodowriteReminder => 'Rappel TodoWrite';

  @override
  String get sessMetaTriggered => 'Déclenché';

  @override
  String get sessMetaNotTriggered => 'Non déclenché';

  @override
  String get sessMetaUnavailable => 'Indisponible';

  @override
  String get sessMetaReminderReason => 'Raison du rappel';

  @override
  String get sessMetaPlanHistory => 'Historique des plans';

  @override
  String get sessMetaRecentErrors => 'Erreurs récentes';

  @override
  String get sessMetaThereAreNoSessionErrorsTo =>
      'Aucune erreur de session à examiner.';

  @override
  String get sessMetaLastPromptMetadata => 'Dernières métadonnées de prompt';

  @override
  String get sessMetaClose => 'Fermer';

  @override
  String get sessMetaPendingApproval => 'En attente d’approbation';

  @override
  String get sessMetaInProgress => 'En cours';

  @override
  String get sessMetaCompleted => 'Terminé';

  @override
  String get sessMetaFailed => 'Échec';

  @override
  String get sessMetaCancelled => 'Annulé';

  @override
  String get sessMetaCreated => 'Créé';

  @override
  String get sessMetaUpdated => 'Mis à jour';

  @override
  String get sessMetaErrorDetail => 'Détail de l’erreur';

  @override
  String get commonDetails => 'Détails';

  @override
  String get commonCopy => 'Copier';

  @override
  String get commonViewDetails => 'Voir les détails';

  @override
  String get commonCopiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get structuredErrorWhy => 'Pourquoi :';

  @override
  String get structuredErrorTry => 'À essayer :';

  @override
  String get structuredErrorServerSays => 'Réponse du serveur :';

  @override
  String get structuredErrorRaw => 'Erreur brute :';

  @override
  String get sessMetaPresented => 'Affiché';

  @override
  String get sessMetaThisSessionEndedEarlyRetryThe =>
      'Cette session s’est terminée prématurément. Réessayez la requête ou poursuivez avec une instruction plus spécifique.';

  @override
  String get sessMetaToolCallsStoppedForSafety =>
      'Appels d’outils arrêtés pour des raisons de sécurité';

  @override
  String get sessMetaOpenhandStoppedThisSessionForSafety =>
      'OpenHand a arrêté cette session pour des raisons de sécurité après trop de tours d’outils consécutifs. Cet arrêt s’est produit dans le contrôleur de session avant que l’outil suivant ne puisse s’exécuter, pas parce qu’une exécution d’outil spécifique a échoué. Demandez à l’assistant de résumer la progression actuelle ou fournissez une étape suivante plus spécifique.';

  @override
  String get sessMetaResponseInterrupted => 'Réponse interrompue';

  @override
  String get sessMetaTheResponseWasInterruptedWhileStreaming =>
      'La réponse a été interrompue pendant la diffusion et cette session s’est arrêtée. Réessayez la requête ou continuez avec un nouveau message.';

  @override
  String get sessMetaRequestFailed => 'Échec de la requête';

  @override
  String get sessMetaTheRequestFailedBeforeTheAssistant =>
      'La requête a échoué avant que l’assistant ne puisse continuer. Vérifiez la configuration et réessayez, ou envoyez un nouveau message.';

  @override
  String get sessMetaContinuationFailed => 'Échec de la continuation';

  @override
  String get sessMetaTheSessionFailedWhileRequestingThe =>
      'La session a échoué lors de la demande du tour suivant de l’assistant après la continuation de l’exécution. Les étapes terminées et les résultats des outils ont été préservés. Répondez par « continue/retry », ou vérifiez la configuration et réessayez.';

  @override
  String get sessMetaSafetyStop => 'Arrêt de sécurité';

  @override
  String get sessMetaStreamError => 'Erreur de flux';

  @override
  String get sessMetaRequestError => 'Erreur de requête';

  @override
  String get sessMetaContinuationError => 'Erreur de continuation';

  @override
  String get sessMetaToolExecutionError => 'Erreur d’exécution d’outil';

  @override
  String get sessMetaCompressionError => 'Erreur de compression';

  @override
  String get sessMetaPromptBlocked => 'Prompt bloqué';

  @override
  String get sessMetaTitleGenerationError => 'Erreur de génération de titre';

  @override
  String get sessMetaSessionError => 'Erreur de session';

  @override
  String get auditNoData => 'Aucune donnée';

  @override
  String get auditCopyJson => 'Copier le JSON';

  @override
  String get auditCopiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get auditMessageAudit => 'Audit du message';

  @override
  String get auditClose => 'Fermer';

  @override
  String get auditOverview => 'Aperçu';

  @override
  String get auditMessageId => 'ID du message';

  @override
  String get auditSessionId => 'ID de session';

  @override
  String get auditRole => 'Rôle';

  @override
  String get auditKind => 'Type';

  @override
  String get auditCharacterCount => 'Nombre de caractères';

  @override
  String get auditStreaming => 'Diffusion';

  @override
  String get auditDeleted => 'Supprimé';

  @override
  String get auditHasError => 'Comporte une erreur';

  @override
  String get auditTiming => 'Synchronisation';

  @override
  String get auditStartedCreated => 'Démarré / Créé';

  @override
  String get auditEnded => 'Terminé';

  @override
  String get auditDurationMs => 'Durée (ms)';

  @override
  String get auditModelTokens => 'Modèle et jetons';

  @override
  String get auditModelId => 'ID du modèle';

  @override
  String get auditModelLabel => 'Étiquette du modèle';

  @override
  String get auditTotalTokens => 'Jetons totaux';

  @override
  String get auditCacheHitRatio => 'Taux de succès du cache';

  @override
  String get auditPromptTokens => 'Jetons d’invite';

  @override
  String get auditCompletionTokens => 'Jetons de réponse';

  @override
  String get auditTokenBreakdown => 'Décomposition des jetons';

  @override
  String get auditError => 'Erreur';

  @override
  String get auditContent => 'Contenu';

  @override
  String get auditFullComposedPromptThatWasActually =>
      'Invite composée complète qui a réellement été envoyée à l’IA pour ce tour (instructions système, catalogue d’outils, mémoire, historique et entrée utilisateur).';

  @override
  String get auditWaitingForComposedPromptInjectionAuto =>
      'En attente de l’injection de l’invite composée (s’actualise automatiquement pendant la diffusion).';

  @override
  String get auditUserRawInput => 'Entrée brute de l’utilisateur';

  @override
  String get auditStructuredPromptTurns => 'Tours d’invite structurés';

  @override
  String get auditNone => 'Aucun';

  @override
  String get auditPromptMetadata => 'Métadonnées de l’invite';

  @override
  String get auditRequest => 'Requête';

  @override
  String get auditMethod => 'Méthode';

  @override
  String get auditHeaders => 'En-têtes';

  @override
  String get auditNotCapturedEnableSettingsAiTelemetry =>
      'Non capturé (activez Paramètres → IA → Débogage de télémétrie)';

  @override
  String get auditBodyQueryPath => 'Corps / Requête / Chemin';

  @override
  String get auditRawAiResponse => 'Réponse IA brute';

  @override
  String get auditExpandRawResponse => 'Développer la réponse brute';

  @override
  String get auditNotCapturedDebugDisabledOrResponse =>
      'Non capturé : débogage désactivé ou réponse indisponible';

  @override
  String get auditAttachments => 'Pièces jointes';

  @override
  String get auditAttachmentList => 'Liste des pièces jointes';

  @override
  String get auditNoAttachments => 'Aucune pièce jointe';

  @override
  String get auditFullMetadata => 'Métadonnées complètes';

  @override
  String get auditMessageMetadata => 'Métadonnées du message';

  @override
  String get auditSessionEnvironment => 'Environnement de session';

  @override
  String get auditEnvironmentSnapshot => 'Instantané de l’environnement';

  @override
  String get auditAuditSnapshotCopied => 'Instantané d’audit copié';

  @override
  String get auditCopyAuditSnapshot => 'Copier l’instantané d’audit';

  @override
  String get auditSessionMetadataSaved => 'Métadonnées de session enregistrées';

  @override
  String get auditSessionAudit => 'Audit de session';

  @override
  String get auditTemplate => 'Modèle';

  @override
  String get auditCreatedAt => 'Créé le';

  @override
  String get auditUpdatedAt => 'Mis à jour le';

  @override
  String get auditMessages => 'Messages';

  @override
  String get auditLastModel => 'Dernier modèle';

  @override
  String get auditTitleEditable => 'Titre (modifiable)';

  @override
  String get auditSessionTitle => 'Titre de session';

  @override
  String get auditSaveTitle => 'Enregistrer le titre';

  @override
  String get auditSessionMetadataEditableJson =>
      'Métadonnées de session (JSON modifiable)';

  @override
  String get auditSaveWritesBackThroughTheSession =>
      'L’enregistrement réécrit via le contrôleur de session avec un diff d’interface en direct ; les clés supprimées sont effacées.';

  @override
  String get auditSaveMetadata => 'Enregistrer les métadonnées';

  @override
  String get auditRuntimePromptMetadataReadOnly =>
      'Métadonnées d’invite d’exécution (lecture seule)';

  @override
  String get auditUsefulForPromptConstructionTroubleshooti =>
      'Utile pour le dépannage de la construction d’invite ; mis à jour automatiquement par l’exécution.';

  @override
  String get auditLastPromptMetadata => 'last_prompt_metadata';

  @override
  String get auditNoRuntimePromptMetadataYet =>
      'Aucune métadonnée d’invite d’exécution pour l’instant';

  @override
  String get auditEnvironment => 'Environnement';

  @override
  String get auditErrorList => 'Liste des erreurs';

  @override
  String get auditNoErrorsRecorded => 'Aucune erreur enregistrée';

  @override
  String get auditTapARowToInspectA =>
      'Appuyez sur une ligne pour inspecter un message ; la suppression la retire du stockage.';

  @override
  String get auditNoMessages => 'Aucun message';

  @override
  String get auditAudit => 'Audit';

  @override
  String get auditDelete => 'Supprimer';

  @override
  String get progExpFESelectOpenedFile => 'Sélectionner le fichier ouvert';

  @override
  String get progExpFEExpandSelected => 'Développer la sélection';

  @override
  String get progExpFECollapseAll => 'Tout réduire';

  @override
  String get progExpFETypeASymbolNameToSearch =>
      'Saisissez un nom de symbole pour rechercher dans les fichiers de l’espace de travail actuel.';

  @override
  String get progExpFENoWorkspaceSymbolBackendIsAvailable =>
      'Aucun back-end de symboles d’espace de travail disponible pour le fichier actuel.';

  @override
  String get progExpFENoMatchingWorkspaceSymbolsWereFound =>
      'Aucun symbole d’espace de travail correspondant trouvé.';

  @override
  String get progExpFEFetchingWorkspaceSymbolsFailedConfirmTha =>
      'Échec de la récupération des symboles d’espace de travail. Vérifiez que le serveur de langue actif prend en charge workspace/symbol.';

  @override
  String get progExpFEThisFileIsStillInLarge =>
      'Ce fichier est encore en mode aperçu de fichier volumineux ; la barre de symboles utilise donc l’extraction locale pour rester réactive.';

  @override
  String get progExpFENoLspSymbolBackendIsAvailable =>
      'Aucun back-end de symboles LSP disponible pour ce fichier ; la barre de symboles est revenue à l’extraction locale.';

  @override
  String get progExpFETheLspServerReturnedAnEmpty =>
      'Le serveur LSP a renvoyé une liste de symboles vide.';

  @override
  String get progExpFEFetchingLspSymbolsFailedSoThe =>
      'Échec de la récupération des symboles LSP ; la barre de symboles est revenue à l’extraction locale.';

  @override
  String get progExpFERenameSymbol => 'Renommer le symbole';

  @override
  String get progExpFEReviewTheDiffForThisRename =>
      'Examinez le diff de ce renommage avant de décider de l’appliquer.';

  @override
  String get progExpFETheRenameWasCancelledAndNo =>
      'Le renommage a été annulé et aucune modification n’a été appliquée.';

  @override
  String get progExpFETheSymbolAtTheCurrentCursor =>
      'Le symbole à la position actuelle du curseur ne peut pas être renommé.';

  @override
  String get progExpFETheLanguageServerDidNotReturn =>
      'Le serveur de langue n’a renvoyé aucune modification à appliquer.';

  @override
  String get progExpFECodeActions => 'Actions de code';

  @override
  String get progExpFENoCodeActionsAreAvailableAt =>
      'Aucune action de code disponible à la position actuelle du curseur.';

  @override
  String get progExpFEReviewTheDiffFromThisCode =>
      'Examinez le diff de cette action de code avant de l’appliquer.';

  @override
  String get progExpFEIfTheLanguageServerCommandRequests =>
      'Si la commande du serveur de langue demande des modifications pendant l’exécution, celles-ci seront également prévisualisées en premier.';

  @override
  String get progExpFETheCodeActionWasCancelledAnd =>
      'L’action de code a été annulée et aucune modification n’a été appliquée.';

  @override
  String get progExpFEExecutedTheLanguageServerCommand =>
      'Commande du serveur de langue exécutée.';

  @override
  String get progExpFESomeLanguageServerRequestedEditsWere =>
      'Certaines modifications demandées par le serveur de langue ont été ignorées.';

  @override
  String get progExpFEThisCodeActionDidNotReturn =>
      'Cette action de code n’a renvoyé aucune modification applicable.';

  @override
  String get progExpFEQuickFix => 'Correction rapide';

  @override
  String get progExpFENoQuickFixesAreAvailableFor =>
      'Aucune correction rapide disponible pour le diagnostic survolé.';

  @override
  String get progExpFENoCodeActionsAreAvailableFor =>
      'Aucune action de code disponible pour le diagnostic survolé.';

  @override
  String get progExpFENoQuickFixesAreAvailableFor2 =>
      'Aucune correction rapide disponible pour cette ligne de diagnostic.';

  @override
  String get progExpFETheCurrentFileIsStillLoading =>
      'Le fichier actuel est encore en cours de chargement, les actions LSP ne sont donc pas encore disponibles.';

  @override
  String get progExpFEThisFileIsStillInLarge2 =>
      'Ce fichier est encore en mode aperçu de fichier volumineux. Ouvrez l’éditeur complet avant de lancer la navigation LSP.';

  @override
  String get progExpFETheCurrentFileIsStillLoading2 =>
      'Le fichier actuel est encore en cours de chargement, les actions d’édition au niveau du document ne sont donc pas encore disponibles.';

  @override
  String get progExpFEThisFileIsStillInLarge3 =>
      'Ce fichier est encore en mode aperçu de fichier volumineux. Ouvrez l’éditeur complet avant de formater.';

  @override
  String get progExpFEFormatDocument => 'Formater le document';

  @override
  String get progExpFETheCurrentFileIsNotReady =>
      'Le fichier actuel n’est pas encore prêt. Réessayez dans un instant.';

  @override
  String get progExpFETheFormatterDidNotReturnAny =>
      'Le formateur n’a renvoyé aucune modification à appliquer.';

  @override
  String get progExpFEFormattingProducedTheSameContentSo =>
      'Le formatage a produit le même contenu, aucun texte n’a donc été modifié.';

  @override
  String get progExpFEGoToDefinition => 'Aller à la définition';

  @override
  String get progExpFENoDefinitionWasFoundAtThe =>
      'Aucune définition trouvée à la position actuelle du curseur.';

  @override
  String get progExpFEMultipleDefinitionsWereFoundChooseA =>
      'Plusieurs définitions trouvées. Choisissez une cible pour naviguer.';

  @override
  String get progExpFEFindReferences => 'Trouver les références';

  @override
  String get progExpFENoReferencesWereFoundAtThe =>
      'Aucune référence trouvée à la position actuelle du curseur.';

  @override
  String get progExpFEHoverInfo => 'Info au survol';

  @override
  String get progExpFEThereIsNoHoverInformationAt =>
      'Aucune information au survol à la position actuelle du curseur.';

  @override
  String get progExpFELspBackend => 'Back-end LSP';

  @override
  String get progExpFEReResolveTheBackendForThe =>
      'Réinitialiser le back-end pour le fichier actuel';

  @override
  String get progExpFEInspectBackendDetails =>
      'Inspecter les détails du back-end';

  @override
  String get progExpFECloseEsc => 'Fermer (Esc)';

  @override
  String get progExpFEToggleComment => 'Basculer le commentaire';

  @override
  String get progExpFEThisLanguageDoesNotHaveA =>
      'Cette langue n’a pas encore de stratégie de commentaire configurée, le basculement de commentaire est donc indisponible.';

  @override
  String get progExpFEGoToImplementation => 'Aller à l’implémentation';

  @override
  String get progExpFESignatureHelp => 'Aide à la signature';

  @override
  String get progExpFEThereIsNoSignatureHelpAvailable =>
      'Aucune aide à la signature disponible à la position actuelle du curseur.';

  @override
  String get progExpFEPreviousMatch => 'Correspondance précédente';

  @override
  String get progExpFENextMatch => 'Correspondance suivante';

  @override
  String get progExpFEMatchCase => 'Respecter la casse';

  @override
  String get progExpFEShowReplace => 'Afficher le remplacement';

  @override
  String get progExpFEReplaceCurrent => 'Remplacer l’occurrence actuelle';

  @override
  String get progExpFEReplaceAll => 'Tout remplacer';

  @override
  String get progExpFECurrentFileSymbols => 'Symboles du fichier actuel';

  @override
  String get progExpFEWorkspaceSymbols => 'Symboles de l’espace de travail';

  @override
  String get progExpFERefreshDiagnostics => 'Actualiser les diagnostics';

  @override
  String get progExpFESymbols => 'Symboles';

  @override
  String get progExpFESymbolNavigationShiftCmdCtrlO =>
      'Navigation des symboles (Shift+Cmd/Ctrl+O)';

  @override
  String get progExpFEWorkspace => 'Espace de travail';

  @override
  String get progExpFEWorkspaceSymbolSearchCmdCtrlT =>
      'Recherche de symboles d’espace de travail (Cmd/Ctrl+T)';

  @override
  String get progExpFEShowDiagnosticsForTheCurrentFile =>
      'Afficher les diagnostics du fichier actuel';

  @override
  String get progExpFEInspectTheLspBackendBoundTo =>
      'Inspecter le back-end LSP lié au fichier actuel';

  @override
  String get progExpFEDef => 'Déf.';

  @override
  String get progExpFEGoToDefinitionF12CmdCtrl =>
      'Aller à la définition (F12 / Cmd/Ctrl+B)';

  @override
  String get progExpFERefs => 'Réfs.';

  @override
  String get progExpFEFindReferencesShiftF12CmdCtrl =>
      'Trouver les références (Shift+F12 / Cmd/Ctrl+Shift+B)';

  @override
  String get progExpFEHover => 'Survol';

  @override
  String get progExpFEHoverInfoCmdCtrlI => 'Info au survol (Cmd/Ctrl+I)';

  @override
  String get progExpFERename => 'Renommer';

  @override
  String get progExpFERenameSymbolF2 => 'Renommer le symbole (F2)';

  @override
  String get progExpFEActions => 'Actions';

  @override
  String get progExpFECodeActionsCmdCtrl => 'Actions de code (Cmd/Ctrl+.)';

  @override
  String get progExpFEFormat => 'Formater';

  @override
  String get progExpFENoImplementationWasFoundAtThe =>
      'Aucune implémentation trouvée à la position actuelle du curseur.';

  @override
  String get progExpFEMultipleImplementationsFoundChooseATarge =>
      'Plusieurs implémentations trouvées. Choisissez une cible pour naviguer.';

  @override
  String get progExpFERefactor => 'Refactoriser';

  @override
  String get progExpFEReviewTheChangesBeforeApplying =>
      'Examinez les modifications avant de les appliquer.';

  @override
  String get progExpFESaveFile => 'Enregistrer le fichier';

  @override
  String get progExpFECloseEditorReturnToSession =>
      'Fermer l’éditeur, retour à la session';

  @override
  String get progExpFEShowQuickFixesForThisDiagnostic =>
      'Afficher les corrections rapides pour cette ligne de diagnostic';

  @override
  String get progExpFELargeFilePerformanceModeIsActive =>
      'Mode performance fichier volumineux actif : aperçu virtualisé en lecture seule utilisé pour éviter les blocages de mise en page complète.';

  @override
  String get progExpFEOpenFullEditorAnyway =>
      'Ouvrir l’éditeur complet quand même';

  @override
  String get settingsShortcuts => 'Raccourcis';

  @override
  String get settingsConfigureKeyCombinationsForCommonActions =>
      'Configurez les combinaisons de touches pour les actions courantes. OpenHand prend en charge jusqu’à quatre touches simultanées.';

  @override
  String get settingsBuiltInTools => 'Outils intégrés';

  @override
  String get settingsCrons => 'Tâches Cron';

  @override
  String get settingsControlsRetentionAndColdStartCleanup =>
      'Contrôle la rétention et le nettoyage au démarrage à froid de l’historique d’exécution cron. Le travailleur de nettoyage s’exécute une fois par démarrage à froid avec délai d’expiration strict, verrou single-flight et défaillances en silentLog uniquement pour ne jamais fuir de ressources ou boucler indéfiniment.';

  @override
  String get settingsHermesTalker => 'Hermes Talker';

  @override
  String get settingsConfigureHermesTalkerSelfLearningEvery =>
      'Configurer l’auto-apprentissage de Hermes Talker : toutes les 5 minutes, un cron système analyse les sessions des 7 derniers jours et envoie un sous-agent restreint pour mettre à jour la mémoire et les compétences en arrière-plan.';

  @override
  String get settingsEditor => 'Éditeur';

  @override
  String get settingsManagePerLanguageLspBackendsInstall =>
      'Gérez les back-ends LSP par langue, les racines d’installation et les paramètres d’assistant de téléchargement. Les mappages enregistrés s’appliquent directement à la navigation, aux diagnostics, au renommage et aux actions de code de l’éditeur.';

  @override
  String get settingsAppData => 'Données de l’application';

  @override
  String get settingsPerResponseToolCallLimit =>
      'Limite d’appels d’outil par réponse';

  @override
  String get settingsSaveLimit => 'Enregistrer la limite';

  @override
  String get settingsSequentialToolRoundLimit =>
      'Limite des tours d’outils consécutifs';

  @override
  String get settingsSessionSettings => 'Paramètres de session';

  @override
  String get settingsConfigureDefaultBehaviourForNewSessions =>
      'Configurez le comportement par défaut des nouvelles sessions, notamment les délais, la récupération du titre, le mode par défaut et les autorisations.';

  @override
  String get settingsSendTimeoutS => 'Délai d’envoi (s)';

  @override
  String get settingsMaximumWaitTimeToEstablishThe =>
      'Temps d’attente maximal pour établir la connexion HTTP et envoyer la requête. Par défaut : 60 s.';

  @override
  String get settingsSaveTimeout => 'Enregistrer le délai';

  @override
  String get settingsResponseTimeoutS => 'Délai de réponse (s)';

  @override
  String get settingsMaximumWaitForACompleteResponse =>
      'Attente maximale d’une réponse complète en mode sans flux. Par défaut : 120 s.';

  @override
  String get settingsStreamIdleTimeoutS => 'Délai d’inactivité du flux (s)';

  @override
  String get settingsMaximumIdleWaitBetweenStreamChunks =>
      'Attente d’inactivité maximale entre les blocs de flux. Au-delà, cela provoque « Request timed out. ». Par défaut : 120 s.';

  @override
  String get settingsAutoTitle => 'Récupération auto du titre';

  @override
  String get settingsWhenEnabledATitleIsAutomatically =>
      'Lorsqu’activé, un titre de session est récupéré après le premier message texte valide d’une nouvelle session.';

  @override
  String get settingsTitleFetchMode => 'Mode de récupération du titre';

  @override
  String get settingsTitleFetchModeDescription =>
      'Asynchrone ne bloque pas la première réponse ; synchrone récupère le titre avant d’envoyer la première requête IA.';

  @override
  String get settingsTitleFetchModeAsync => 'Asynchrone';

  @override
  String get settingsTitleFetchModeSync => 'Synchrone';

  @override
  String get settingsDefaultSessionMode => 'Mode de session par défaut';

  @override
  String get settingsDefaultInteractionModeForNewSessions =>
      'Mode d’interaction par défaut pour les nouvelles sessions : Chat ou Plan.';

  @override
  String get settingsChat => 'Discussion';

  @override
  String get settingsPlan => 'Plan';

  @override
  String get settingsDefaultFullAccess => 'Accès complet par défaut';

  @override
  String get settingsWhenEnabledNewSessionsStartIn =>
      'Lorsqu’activé, les nouvelles sessions démarrent en mode accès complet, permettant à l’IA d’exécuter des opérations de fichier et de commande sans confirmation par action.';

  @override
  String get settingsUserProfile => 'Profil utilisateur';

  @override
  String get settingsMaintainAGlobalUserProfileLanguage =>
      'Maintenez un profil utilisateur global (style de langue, domaines d’intérêt, préférences de communication). Lorsqu’il n’est pas vide, le profil est intégré à l’invite système de chaque modèle de fil pour que l’IA paraisse personnalisée ; l’auto-apprentissage l’affine progressivement.';

  @override
  String get settingsModelProviderManagement =>
      'Gestion des fournisseurs de modèles';

  @override
  String get settingsAddSelectTestAndMaintainModel =>
      'Ajoutez, sélectionnez, testez et maintenez les configurations des fournisseurs de modèles. Chaque fournisseur peut servir plusieurs modèles.';

  @override
  String get settingsCompressionTrigger => 'Déclencheur de compression';

  @override
  String get settingsOnceTheUncompressedHistoryInA =>
      'Une fois que l’historique non compressé d’un fil dépasse cette valeur, OpenHand crée un nouveau point de contrôle de résumé.';

  @override
  String get settingsToolCallOutputCompressionThreshold =>
      'Seuil de compression de la sortie d’appel d’outil';

  @override
  String get settingsWhenAToolCallReturnsMore =>
      'Utilisé uniquement lors de la création des points de compression : les anciens résultats d’outils dépassant ce seuil deviennent des résumés structurés. Les conversations normales transmettent toujours les résultats complets au modèle. Valeur par défaut : 1024.';

  @override
  String get settingsDefaultsTo40IfOneAssistant =>
      'Par défaut 40. Si une réponse d’assistant dépasse ce nombre d’appels d’outil, OpenHand envoie un avertissement et arrête le tour en toute sécurité.';

  @override
  String get settingsDefaultsTo24RoundsIfThe =>
      'Par défaut 24 tours. Si l’assistant continue de demander un autre tour d’outil après chaque exécution, OpenHand s’arrête une fois cette limite atteinte pour éviter les boucles d’outils incontrôlées.';

  @override
  String get settingsImageSizeLimit => 'Limite de taille d’image';

  @override
  String get settingsDefaultsTo1mbImageAttachmentsLarger =>
      'Par défaut 1 Mo. Les pièces jointes d’image dépassant cette limite sont automatiquement compressées avant l’ouverture de l’éditeur et stockées dans la limite, gardant les sessions et invites compactes.';

  @override
  String get settingsCostControl => 'Contrôle des coûts';

  @override
  String get settingsReduceTokenCostsByFreezingThe =>
      'Réduisez les coûts en jetons en stabilisant le préfixe statique du prompt et en appliquant des indices de cache au niveau du protocole. Si activé, le fournisseur, le modèle et l’intensité de raisonnement sont verrouillés dès que l’IA commence à répondre au premier message utilisateur valide ; Prompt Builder garde autant que possible les instructions système, le catalogue d’outils, la mémoire et les instructions utilisateur en sections stables au début ; Anthropic injecte les points cache_control, et les requêtes compatibles OpenAI utilisent une affinité de cache stable avec un corps où messages reste en dernier.';

  @override
  String get settingsEnableInputCache => 'Activer le cache d’entrée';

  @override
  String get settingsDisabledByDefaultWhenEnabledEvery =>
      'Activé par défaut. Si désactivé, OpenHand n’injecte pas d’indices de cache au niveau du protocole et n’applique pas les protections de cache d’entrée comme le verrouillage du modèle. Pour maximiser le taux de succès, évitez de modifier fréquemment les outils, compétences, MCP, mémoire ou instructions en cours de session.';

  @override
  String get settingsCacheBreakpointUpdateMode =>
      'Mode de mise à jour des candidats d’historique';

  @override
  String get settingsChooseTheSlidingUnitForThe =>
      'L’ancre stable, la fin de la requête précédente et la fin actuelle sont prioritaires. Ce réglage sélectionne uniquement les candidats d’historique restants.';

  @override
  String get settingsByMessageCountUserAssistant =>
      'Par nombre de messages (utilisateur+assistant)';

  @override
  String get settingsByUserMessageCountOnly =>
      'Par nombre de messages utilisateur uniquement';

  @override
  String get settingsByAccumulatedTokens => 'Par jetons cumulés';

  @override
  String get settingsCacheBreakpointUpdateInterval =>
      'Intervalle des candidats d’historique';

  @override
  String get settingsDefault10MeaningDependsOnThe =>
      'Par défaut 10. Utilisé uniquement pour les candidats d’historique automatiques ; l’unité dépend du mode ci-dessus.';

  @override
  String get settingsSave => 'Enregistrer';

  @override
  String get settingsCacheBreakpointCount =>
      'Nombre de points d’arrêt de cache';

  @override
  String get settingsDefault4Range14Anthropic =>
      'Par défaut 4, plage 1-4. Anthropic affecte d’abord le budget à l’ancre système/outils stable, à la fin de la requête précédente et à la fin actuelle, puis aux candidats d’historique. Chaque requête accepte au plus 4 marqueurs cache_control. Les fournisseurs compatibles OpenAI ne reçoivent pas ces marqueurs.';

  @override
  String get settingsCommandSafety => 'Sécurité des commandes';

  @override
  String get settingsControlWriteCommandConfirmationForBash =>
      'Contrôlez la confirmation d’écriture de commande pour bash et gérez les règles de refus en un seul endroit.';

  @override
  String get settingsWriteCommandConfirmation =>
      'Confirmation de commande d’écriture';

  @override
  String get settingsEnabledByDefaultWhenTheAi =>
      'Activé par défaut. Lorsque l’IA essaie d’exécuter une commande bash de type écriture, OpenHand demande d’abord votre confirmation.';

  @override
  String get settingsAllowCommandList => 'Liste des commandes autorisées';

  @override
  String get settingsMatchingWriteLikeBashCommandsSkip =>
      'Les commandes bash de type écriture correspondantes ignorent la boîte de dialogue de confirmation et s’exécutent immédiatement. Utilisez ceci uniquement pour des modèles de commande stables auxquels vous faites explicitement confiance.';

  @override
  String get settingsAddAllowRule => 'Ajouter une règle d’autorisation';

  @override
  String get settingsNoAllowRulesConfigured =>
      'Aucune règle d’autorisation configurée';

  @override
  String get settingsAddARuleToLetMatching =>
      'Ajoutez une règle pour que les commandes d’écriture correspondantes contournent la confirmation.';

  @override
  String get settingsDenyCommandList => 'Liste des commandes refusées';

  @override
  String get settingsMatchingBashCommandsAreBlockedBefore =>
      'Les commandes bash correspondantes sont bloquées avant l’exécution et le résultat de refus est renvoyé au modèle à la place. Prend en charge les expressions régulières et les motifs génériques simples comme « rm * ».';

  @override
  String get settingsAddRule => 'Ajouter une règle';

  @override
  String get settingsNoDenyRulesConfigured =>
      'Aucune règle de refus configurée';

  @override
  String get settingsAddARuleToBlockMatching =>
      'Ajoutez une règle pour bloquer les commandes bash correspondantes avant leur exécution.';

  @override
  String get settingsTelemetry => 'Télémétrie';

  @override
  String get settingsWhenEnabledOpenhandCapturesRawAi =>
      'Lorsqu’activé, OpenHand capture les réponses IA brutes, les paramètres de requête, les temps et les erreurs afin que vous puissiez les inspecter depuis les boîtes de dialogue d’audit de message/session.';

  @override
  String get settingsDebugMode => 'Mode débogage';

  @override
  String get settingsOffByDefaultWhenEnabledEvery =>
      'Désactivé par défaut. Lorsqu’activé, chaque carte de message expose une pilule d’audit au survol/focus et chaque barre d’outils de session affiche une action d’audit au niveau de la session.';

  @override
  String get settingsCaptureRawPayload => 'Capturer la charge utile brute';

  @override
  String get settingsEnabledByDefaultOnlyActiveWhen =>
      'Activé par défaut. Actif uniquement lorsque le mode débogage est activé. Joint les blocs JSON/SSE bruts aux métadonnées du message pour audit.';

  @override
  String get settingsCaptureEnvironment => 'Capturer l’environnement';

  @override
  String get settingsOffByDefaultOnlyActiveWhen =>
      'Désactivé par défaut. Actif uniquement lorsque le mode débogage est activé. Joint le répertoire de travail, les détails de la plateforme et les variables d’environnement du processus (peut contenir des secrets) aux métadonnées du message — activez avec précaution.';

  @override
  String get settingsShortcutBindings => 'Affectations de raccourcis';

  @override
  String get settingsClickRecordThenPressTheNew =>
      'Cliquez sur Enregistrer, puis appuyez sur la nouvelle combinaison de touches pour mettre à jour une affectation. Le changement de modèle et de session boucle automatiquement.';

  @override
  String get settingsShortcutRecord => 'Enregistrer';

  @override
  String get settingsShortcutResetToDefault => 'Réinitialiser';

  @override
  String get settingsShortcutMaxKeysError =>
      'OpenHand prend en charge jusqu’à quatre touches simultanées.';

  @override
  String get settingsShortcutRecorderBody =>
      'Appuyez sur la nouvelle combinaison de touches pour mettre à jour cette affectation. OpenHand prend en charge jusqu’à quatre touches simultanées.';

  @override
  String get settingsShortcutRecorderTip =>
      'Astuce : incluez au moins une touche non modificatrice, comme Entrée, P ou une flèche.';

  @override
  String get settingsAutoCleanupExecutionHistory =>
      'Nettoyage automatique de l’historique d’exécution';

  @override
  String get settingsOnEveryColdStartAnAsync =>
      'À chaque démarrage à froid, un travailleur asynchrone s’exécute une fois pour supprimer l’historique plus ancien que la fenêtre de rétention. Le travailleur est single-flight, possède un délai d’expiration strict et journalise silencieusement les échecs pour ne jamais bloquer l’interface ni boucler indéfiniment.';

  @override
  String get settingsEnableSelfLearning => 'Activer l’auto-apprentissage';

  @override
  String get settingsWhenOffTheSchedulerSkipsEvery =>
      'Lorsque désactivé, le planificateur saute chaque session Hermes Talker. L’entrée cron système est préservée mais ne déclenche jamais de sous-agent.';

  @override
  String get settingsShowSelfLearningMessages =>
      'Afficher les messages d’auto-apprentissage';

  @override
  String get settingsWhenOffSelfLearningCardsAre =>
      'Lorsque désactivé, les cartes « auto-apprentissage » sont masquées dans la transcription du chat (l’apprentissage en arrière-plan continue). Activé par défaut.';

  @override
  String get settingsToolCatalogOverview => 'Aperçu du catalogue d’outils';

  @override
  String get settingsResetAll => 'Tout réinitialiser';

  @override
  String get settingsEnableAll => 'Tout activer';

  @override
  String get settingsDisableAll => 'Tout désactiver';

  @override
  String get settingsNoBuiltInToolConfigurations =>
      'Aucune configuration d’outil intégré';

  @override
  String get settingsClickResetAllToRestoreThe =>
      'Cliquez sur « Tout réinitialiser » pour restaurer la liste d’outils par défaut.';

  @override
  String get settingsResetBuiltInToolConfigs =>
      'Réinitialiser les configurations d’outils intégrés';

  @override
  String get settingsCancel => 'Annuler';

  @override
  String get settingsReset => 'Réinitialiser';

  @override
  String get settingsDeleteCustomTool => 'Supprimer l’outil personnalisé';

  @override
  String get settingsDelete => 'Supprimer';

  @override
  String get settingsSendTimeoutSaved => 'Délai d’envoi enregistré.';

  @override
  String get settingsResponseTimeoutSaved => 'Délai de réponse enregistré.';

  @override
  String get settingsStreamIdleTimeoutSaved =>
      'Délai d’inactivité du flux enregistré.';

  @override
  String get settingsCacheBreakpointUpdateIntervalSaved =>
      'Intervalle des candidats d’historique enregistré';

  @override
  String get settingsCacheBreakpointCountSaved =>
      'Nombre de points d’arrêt de cache enregistré';

  @override
  String get settingsCacheBreakpointPositions =>
      'Candidats de cache d’historique';

  @override
  String get settingsCacheBreakpointPositionsSaved =>
      'Candidats de cache d’historique enregistrés';

  @override
  String get cacheBarTopDescription =>
      'Les bandes colorées illustrent uniquement la structure du prompt. Les épingles P indiquent des candidats dans l’historique ; l’épingle pointillée à droite est l’ancre de fin de la requête actuelle. Les ancres stables et de fin continues sont prioritaires.';

  @override
  String get cacheBarSectionSysLabel => '[0] Système';

  @override
  String get cacheBarSectionDevLabel => '[1] Développeur';

  @override
  String get cacheBarSectionToolsLabel => '[2] Outils';

  @override
  String get cacheBarSectionStateLabel => '[3s/3d] État';

  @override
  String get cacheBarSectionMemoryLabel => '[4] Mémoire';

  @override
  String get cacheBarSectionUserInstLabel => '[4.5] Inst.';

  @override
  String get cacheBarSectionSummaryLabel => '[5] Résumé';

  @override
  String get cacheBarSectionHistoryLabel => 'Historique';

  @override
  String get cacheBarSectionLatestLabel => 'Queue / récent';

  @override
  String get cacheBarSectionSysSummary =>
      'Instructions système du modèle, instructions de l’espace de travail et instantané de l’environnement (OS / cwd / résumé du dépôt).';

  @override
  String get cacheBarSectionSysCacheHint =>
      'Compatible avec le cache : très stable d’un tour à l’autre — point de rupture idéal en premier.';

  @override
  String get cacheBarSectionDevSummary =>
      'Règles de comportement du template de prompt actif (format de sortie & garde-fous).';

  @override
  String get cacheBarSectionDevCacheHint =>
      'Compatible avec le cache : change rarement au cours d’une session.';

  @override
  String get cacheBarSectionToolsSummary =>
      'Catalogue des outils intégrés, capacités MCP et chargeurs de skills appelables par le modèle (avec règles d’invocation DSML).';

  @override
  String get cacheBarSectionToolsCacheHint =>
      'Plutôt stable : touche le cache sauf si le registre des outils change.';

  @override
  String get cacheBarSectionStateSummary =>
      'Métadonnées de session JSON : compteurs, liste de tâches, indicateurs de plan, pièces jointes.';

  @override
  String get cacheBarSectionStateCacheHint =>
      'Volatile : les compteurs avancent à chaque tour — un cache placé ici échoue souvent.';

  @override
  String get cacheBarSectionMemorySummary =>
      'Faits de mémoire utilisateur à long terme intégrés comme connaissances tacites.';

  @override
  String get cacheBarSectionMemoryCacheHint =>
      'Plutôt stable : ne change que lorsque les entrées de mémoire sont modifiées.';

  @override
  String get cacheBarSectionUserInstSummary =>
      'Fragments de prompt réutilisables rédigés par l’utilisateur (directives au niveau du projet).';

  @override
  String get cacheBarSectionUserInstCacheHint =>
      'Stable : rarement modifié ; on peut placer un point de rupture juste après cette bande.';

  @override
  String get cacheBarSectionSummarySummary =>
      'Résumé compressé des conversations antérieures + extraits récents.';

  @override
  String get cacheBarSectionSummaryCacheHint =>
      'Évolution lente : actualisé lors de la compression.';

  @override
  String get cacheBarSectionHistorySummary =>
      'Tours utilisateur / assistant / outil passés dans la session courante.';

  @override
  String get cacheBarSectionHistoryCacheHint =>
      'Append-only : un point de rupture en milieu d’historique survit aux nouveaux tours en queue.';

  @override
  String get cacheBarSectionLatestSummary =>
      'Le message utilisateur en cours de réponse (avec métadonnées des pièces jointes).';

  @override
  String get cacheBarSectionLatestCacheHint =>
      'Change à chaque tour : l’ancre de fin actuelle couvre cette zone, tandis que l’ancre précédente préserve la continuité.';

  @override
  String get cacheBarDynamicTooltip =>
      'Ancre de fin de la requête actuelle — suit toujours le dernier message.';

  @override
  String get cacheBarDynamicSuffix => '(fin actuelle)';

  @override
  String get cacheBarResetEven => 'Réinitialiser uniformément';

  @override
  String get settingsAiBudgetUsdPerSession => 'Budget par session (USD)';

  @override
  String get settingsAiBudgetUsdPerSessionBody =>
      '0 désactive l’alerte. Lorsque le coût estimé cumulé d’une session dépasse ce plafond, la boîte de dialogue des métadonnées met le total en surbrillance dans une couleur d’avertissement. Simple rappel doux — n’interrompt jamais la conversation ni ne bloque l’envoi.';

  @override
  String get settingsAiBudgetUsdPerSessionInvalid =>
      'Veuillez saisir un nombre non négatif entre 0 et 100000.';

  @override
  String get settingsAiBudgetUsdPerSessionSaved =>
      'Budget par session enregistré';

  @override
  String sessionMetadataOverBudgetNotice(String total, String budget) {
    return 'Le coût estimé $total de la session actuelle a dépassé le budget $budget. Simple rappel doux — l’envoi n’est pas affecté.';
  }

  @override
  String get settingsEnterAToolCallLimitGreater =>
      'Saisissez une limite d’appel d’outil supérieure à 0.';

  @override
  String get settingsThePerResponseToolCallLimit =>
      'Limite d’appels d’outil par réponse enregistrée.';

  @override
  String get settingsEnterASequentialToolRoundLimit =>
      'Saisissez une limite de tours d’outils consécutifs supérieure à 0.';

  @override
  String get settingsTheSequentialToolRoundLimitHas =>
      'Limite des tours d’outils consécutifs enregistrée.';

  @override
  String get settingsDeleteDenyRule => 'Supprimer la règle de refus';

  @override
  String get settingsTheDenyCommandRuleHasBeen =>
      'Règle de commande de refus supprimée.';

  @override
  String get settingsDeleteAllowRule => 'Supprimer la règle d’autorisation';

  @override
  String get settingsTheAllowCommandRuleHasBeen =>
      'Règle de commande d’autorisation supprimée.';

  @override
  String get settingsTheShortcutHasBeenUpdated =>
      'Le raccourci a été mis à jour.';

  @override
  String get settingsTheEditorShortcutHasBeenUpdated =>
      'Le raccourci d’éditeur a été mis à jour.';

  @override
  String get settingsSendMessage => 'Envoyer le message';

  @override
  String get settingsCollapseOrExpandComposer =>
      'Réduire ou développer la zone de saisie';

  @override
  String get settingsPreviousModel => 'Modèle précédent';

  @override
  String get settingsNextModel => 'Modèle suivant';

  @override
  String get settingsToggleAutoFollow => 'Basculer le suivi automatique';

  @override
  String get settingsPreviousSession => 'Session précédente';

  @override
  String get settingsNextSession => 'Session suivante';

  @override
  String get settingsSaveFile => 'Enregistrer le fichier';

  @override
  String get settingsTriggerCompletion => 'Déclencher la complétion';

  @override
  String get settingsShowSignatureHelp => 'Afficher l’aide à la signature';

  @override
  String get settingsFind => 'Rechercher';

  @override
  String get settingsFindAndReplace => 'Rechercher et remplacer';

  @override
  String get settingsGoToLine => 'Aller à la ligne';

  @override
  String get settingsDocumentSymbols => 'Symboles du document';

  @override
  String get settingsWorkspaceSymbols => 'Symboles de l’espace de travail';

  @override
  String get settingsGoToDefinition => 'Aller à la définition';

  @override
  String get settingsFindReferences => 'Trouver les références';

  @override
  String get settingsGoToImplementation => 'Aller à l’implémentation';

  @override
  String get settingsShowHoverInfo => 'Afficher l’info au survol';

  @override
  String get settingsRenameSymbol => 'Renommer le symbole';

  @override
  String get settingsCodeActions => 'Actions de code';

  @override
  String get settingsFormatDocument => 'Formater le document';

  @override
  String get settingsDefaultsToCtrlEnterAndTriggers =>
      'Par défaut Ctrl + Enter ; déclenche le bouton d’envoi lorsque la zone de saisie du chat est prête.';

  @override
  String get settingsDefaultsToCtrlPForQuickly =>
      'Par défaut Ctrl + P pour réduire ou développer rapidement la zone de saisie.';

  @override
  String get settingsDefaultsToCtrlLeftAndWraps =>
      'Par défaut Ctrl + Gauche et boucle au dernier modèle si nécessaire.';

  @override
  String get settingsDefaultsToCtrlRightAndWraps =>
      'Par défaut Ctrl + Droite et boucle au premier modèle si nécessaire.';

  @override
  String get settingsDefaultsToCtrlSForToggling =>
      'Par défaut Ctrl + S pour basculer le suivi automatique.';

  @override
  String get settingsDefaultsToCtrlUpAndWraps =>
      'Par défaut Ctrl + Haut et boucle à la fin de la liste de sessions.';

  @override
  String get settingsDefaultsToCtrlDownAndWraps =>
      'Par défaut Ctrl + Bas et boucle au début de la liste de sessions.';

  @override
  String get settingsUndoLastFileMutation =>
      'Annuler la dernière modification de fichier';

  @override
  String get settingsDefaultsToCtrlShiftZForUndo =>
      'Par défaut Ctrl + Maj + Z. Annule la modification de fichier la plus récente du journal de la session courante.';

  @override
  String get auditDeleteMessage => 'Supprimer le message';

  @override
  String get auditDeleteThisMessageThisCannotBe =>
      'Supprimer ce message ? Cette action est irréversible.';

  @override
  String get auditCancel => 'Annuler';

  @override
  String get settingsManageTheBuiltInAiTools =>
      'Gérez les outils IA intégrés. Ajustez l’état d’activation, le nom, la description, le schéma, la priorité, etc., de chaque outil.';

  @override
  String get settingsManageTheLocalFilesAndDatabase =>
      'Gérez les fichiers locaux et les tables de base de données qu’OpenHand possède sur disque. Chaque nettoyage s’exécute sur des travailleurs en arrière-plan pour ne pas bloquer l’interface.';

  @override
  String get settingsThisWillRestoreAllBuiltIn =>
      'Ceci restaurera toutes les configurations d’outils intégrés aux valeurs d’usine, y compris le nom, la description, le schéma, etc.';

  @override
  String get tlCallUnwrap => 'Annuler le retour à la ligne';

  @override
  String get tlCallWrapLines => 'Renvoyer les lignes à la ligne';

  @override
  String get tlCallViewCompressedContent => 'Voir le contenu compressé';

  @override
  String get tlCallViewFullContent => 'Voir le contenu complet';

  @override
  String get tlCallPreparing => 'Préparation';

  @override
  String get tlCallPreparingAlt => 'Préparation';

  @override
  String get tlCallRunningAlt => 'En cours';

  @override
  String get tlCallCompleted => 'Terminé';

  @override
  String get tlCallCompletedAlt => 'Terminé';

  @override
  String get tlCallTimedOutAlt => 'Délai dépassé';

  @override
  String get tlCallFailedAlt => 'Échec';

  @override
  String tlCallFailedToOpenFileLocationError(Object error) {
    return 'Impossible d’ouvrir l’emplacement du fichier : $error';
  }

  @override
  String tlCallMemoryitemsLengthMemoriesUpdated(Object memoryItems_length) {
    return '$memoryItems_length mémoires mises à jour';
  }

  @override
  String tlCallProfileitemsLengthProfileChanges(Object profileItems_length) {
    return '$profileItems_length modifications de profil';
  }

  @override
  String tlCallSkillitemsLengthSkillsUpdated(Object skillItems_length) {
    return '$skillItems_length compétences mises à jour';
  }

  @override
  String get tlCallAiThinkingStreaming => 'IA en réflexion (en flux)';

  @override
  String get tlCallAiThinking => 'IA en réflexion';

  @override
  String get tlCallAiResponseStreaming => 'Réponse IA (en flux)';

  @override
  String get tlCallAiResponse => 'Réponse IA';

  @override
  String tlCallAndItemsLength3More(Object items_length_3, Object items_length) {
    return ' et $items_length_3 autres';
  }

  @override
  String tlCallSecondsSAgo(Object seconds) {
    return 'il y a ${seconds}s';
  }

  @override
  String tlCallMinutesMAgo(Object minutes) {
    return 'il y a $minutes min';
  }

  @override
  String tlCallHoursHAgo(Object hours) {
    return 'il y a $hours h';
  }

  @override
  String tlCallDaysDAgo(Object days) {
    return 'il y a $days j';
  }

  @override
  String sessMetaPlanPlanindex(Object planIndex) {
    return 'Plan #$planIndex';
  }

  @override
  String sessMetaTheCurrentSequentialToolRoundLimit(Object configuredLimit) {
    return 'La limite actuelle des tours d’outils consécutifs est $configuredLimit.';
  }

  @override
  String auditInvalidJsonErrorMessage(Object error_message) {
    return 'JSON invalide : $error_message';
  }

  @override
  String auditSaveFailedError(Object error) {
    return 'Échec de l’enregistrement : $error';
  }

  @override
  String auditRecentErrorsSessionRecenterrorsLength(
    Object session_recentErrors_length,
  ) {
    return 'Erreurs récentes ($session_recentErrors_length)';
  }

  @override
  String auditMessagesSessionMessagesLength(Object session_messages_length) {
    return 'Messages ($session_messages_length)';
  }

  @override
  String progExpFEAppliedEditsLengthFormattingEdits(Object edits_length) {
    return '$edits_length modifications de formatage appliquées.';
  }

  @override
  String progExpFEFormatTheCurrentFileFormatshortcut(Object formatShortcut) {
    return 'Formater le fichier actuel ($formatShortcut)';
  }

  @override
  String progExpFENoCodeactionkindRefactoringIsAvailableAt(
    Object codeActionKind,
  ) {
    return 'Aucun refactoring « $codeActionKind » disponible à la position actuelle.';
  }

  @override
  String get progExpFEHideFileBrowser => 'Masquer l’explorateur de fichiers';

  @override
  String get progExpFEShowFileBrowser => 'Afficher l’explorateur de fichiers';

  @override
  String settingsRetentionWindowRetentionDayS(Object retention) {
    return 'Fenêtre de rétention : $retention jour(s)';
  }

  @override
  String settingsRangeMinrMaxrDaysDefault7(Object minR, Object maxR) {
    return 'Plage $minR–$maxR jours ; par défaut 7. Prend effet au prochain démarrage à froid.';
  }

  @override
  String settingsConcurrentWorkersConcurrency(Object concurrency) {
    return 'Travailleurs simultanés : $concurrency';
  }

  @override
  String settingsCapsHowManySessionsCanBe(Object minC, Object maxC) {
    return 'Plafonne le nombre de sessions pouvant être réparties en parallèle par tick ($minC–$maxC). Par défaut 5.';
  }

  @override
  String settingsSortedLengthBuiltInToolsEnabledcount(
    Object sorted_length,
    Object enabledCount,
  ) {
    return '$sorted_length outils intégrés, $enabledCount activés. Ajustez le nom, la description, le schéma, la priorité, etc.';
  }

  @override
  String settingsAreYouSureYouWantTo(Object config_effectiveName) {
    return 'Voulez-vous vraiment supprimer « $config_effectiveName » ? Cette action est irréversible.';
  }

  @override
  String settingsEnterAValueBetweenMinAnd(Object min, Object max) {
    return 'Saisissez une valeur entre $min et $max secondes.';
  }

  @override
  String settingsPleaseEnterAnIntegerBetweenAppsettingssn(
    Object AppSettingsSnapshot_minAiInputCacheUpdateInterval,
    Object AppSettingsSnapshot_maxAiInputCacheUpdateInterval,
  ) {
    return 'Veuillez saisir un entier entre $AppSettingsSnapshot_minAiInputCacheUpdateInterval et $AppSettingsSnapshot_maxAiInputCacheUpdateInterval.';
  }

  @override
  String settingsPleaseEnterAnIntegerBetweenAppsettingssn2(
    Object AppSettingsSnapshot_minAiInputCacheBreakpointCount,
    Object AppSettingsSnapshot_maxAiInputCacheBreakpointCount,
  ) {
    return 'Veuillez saisir un entier entre $AppSettingsSnapshot_minAiInputCacheBreakpointCount et $AppSettingsSnapshot_maxAiInputCacheBreakpointCount.';
  }

  @override
  String settingsDragTheThumbcountThumbsToPosition(Object thumbCount) {
    return 'Faites glisser $thumbCount points pour définir les candidats d’historique (0%-100%). Les ancres stables et de fin continues utilisent d’abord le budget ; le point de droite reste fixé à la fin actuelle.';
  }

  @override
  String get settingsTheDenyCommandRuleHasBeen2 =>
      'Règle de commande de refus mise à jour.';

  @override
  String get settingsTheAllowCommandRuleHasBeen2 =>
      'Règle de commande d’autorisation mise à jour.';

  @override
  String settingsDefaultsToDefaultlabelAndSavesThe(Object defaultLabel) {
    return 'Par défaut $defaultLabel et enregistre le fichier actuel.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndOpensThe(Object defaultLabel) {
    return 'Par défaut $defaultLabel et ouvre la fenêtre de complétion à la demande.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsMethod(Object defaultLabel) {
    return 'Par défaut $defaultLabel et affiche les signatures de méthode, les détails des paramètres et la documentation récapitulative pour le symbole actuel.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe(Object defaultLabel) {
    return 'Par défaut $defaultLabel et bascule le panneau de recherche.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe2(Object defaultLabel) {
    return 'Par défaut $defaultLabel et bascule le panneau de remplacement.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe3(Object defaultLabel) {
    return 'Par défaut $defaultLabel et bascule le panneau aller-à-la-ligne.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe4(Object defaultLabel) {
    return 'Par défaut $defaultLabel et bascule la liste des symboles du fichier actuel.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe5(Object defaultLabel) {
    return 'Par défaut $defaultLabel et bascule le panneau de recherche de symboles d’espace de travail.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndJumpsTo(Object defaultLabel) {
    return 'Par défaut $defaultLabel et saute à la définition du symbole actuel.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndFindsReferences(Object defaultLabel) {
    return 'Par défaut $defaultLabel et trouve les références pour le symbole actuel.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndJumpsTo2(Object defaultLabel) {
    return 'Par défaut $defaultLabel et saute à l’implémentation actuelle.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsType(Object defaultLabel) {
    return 'Par défaut $defaultLabel et affiche les informations de type ou de documentation à la position actuelle.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndStartsRename(Object defaultLabel) {
    return 'Par défaut $defaultLabel et démarre le renommage pour le symbole actuel.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsAvailable(Object defaultLabel) {
    return 'Par défaut $defaultLabel et affiche les actions de code disponibles.';
  }

  @override
  String settingsDefaultsToDefaultlabelAndFormatsThe(Object defaultLabel) {
    return 'Par défaut $defaultLabel et formate le fichier de programmation actuel ; Shift+Tab effectue d’abord un retrait inverse.';
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
    return '$lspName résolu pour le fichier actuel.\nLangue du projet : $projLang\nLangue du fichier actuel : $fileLang\n$modeLine\n$sdkSourceLine\n$lspSourceLine\nEspace de travail : $rootPath\nCommande : $command';
  }

  @override
  String get settingsReduceMotionLabel => 'Réduire les animations';

  @override
  String get settingsReduceMotionBody =>
      'Lorsque cette option est activée, les animations personnalisées et intégrées sont ignorées (durées ramenées à zéro). Se combine avec le réglage d’accessibilité « Réduire les animations » du système.';

  @override
  String get mcpToolSearchReplayLastCancelAction =>
      'Rejouer dernière annulation';

  @override
  String get mcpToolSearchReplayLastCancelToastFired =>
      'Dernier chargement annulé rejoué';

  @override
  String get mcpToolSearchReplayLastCancelToastEmpty => 'Rien à rejouer';

  @override
  String get aiThrottleSettingsLabel => 'Paramètres de limitation';

  @override
  String get aiThrottleSettingsBody =>
      'Limitation unifiée du streaming : interrupteur principal, mode auto, débit caractères / cartes, durée.';

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
  String get webReverseSetupTargetUrl => 'URL cible *';

  @override
  String get webReverseSetupObjective => 'Objectif *';

  @override
  String get webReverseSetupObjectiveHint =>
      'p. ex. rétro-ingénierie de l’API de téléchargement de fonds d’écran en script curl';

  @override
  String get webReverseSetupTriggerActions =>
      'Actions déclencheuses (facultatif)';

  @override
  String get webReverseSetupTriggerHint =>
      'p. ex. se connecter puis cliquer sur « Télécharger l’original »';

  @override
  String get webReverseSetupLoginMode => 'Mode de connexion';

  @override
  String get webReverseSetupBrowser => 'Navigateur (détecté)';

  @override
  String get webReverseSetupProxy => 'Proxy (facultatif)';

  @override
  String get webReverseSetupKeywords =>
      'Mots-clés (facultatif, séparés par des virgules)';

  @override
  String get webReverseSetupCreateThread => 'Créer le fil';

  @override
  String get webReverseSetupHeaderTitle => 'Nouvelle session Web Reverse';

  @override
  String get webReverseSetupHeaderSubtitle =>
      'Après le démarrage, le navigateur s’ancre à droite de la fenêtre principale';

  @override
  String get webReverseSetupClose => 'Fermer';

  @override
  String get webReverseSetupProfileDir => 'Répertoire de profil';

  @override
  String get webReverseSetupLockDetected =>
      'SingletonLock / lockfile résiduel détecté — peut bloquer le prochain lancement.';

  @override
  String get webReverseSetupWorking => 'Traitement…';

  @override
  String webReverseSetupCooldown(int seconds) {
    return 'Refroidissement ${seconds}s';
  }

  @override
  String get webReverseSetupResolveLock => 'Résoudre le conflit de profil';

  @override
  String get webReverseSignatureDiffHeaderTitle =>
      'Localisateur de variable de champ de signature';

  @override
  String get webReverseSignatureDiffHeaderSubtitle =>
      'Identifie les champs dynamiques (sign / ts / nonce) vs. stables à travers plusieurs captures du même endpoint';

  @override
  String get webReverseSignatureDiffRefresh => 'Actualiser';

  @override
  String get webReverseSignatureDiffSearchHint => 'Rechercher un endpoint';

  @override
  String get webReverseSignatureDiffNoGroups =>
      'Aucun groupe analysable (≥2 échantillons requis)';

  @override
  String get webReverseSignatureDiffEmptyHint =>
      'Déclenchez la même API plusieurs fois dans le panneau Network, puis revenez ici pour analyser.';

  @override
  String get webReverseSignatureDiffCopyReport => 'Copier le rapport';

  @override
  String get webReverseSignatureDiffStable => 'Stable';

  @override
  String get webReverseSignatureDiffDynamic => 'Dynamique';

  @override
  String get webReverseSignatureDiffIncreasing => 'Croissant';

  @override
  String get webReverseSignatureDiffFixedHash => 'Hash longueur fixe';

  @override
  String get webReverseSignatureDiffSectionQuery => 'Paramètres Query';

  @override
  String get webReverseSignatureDiffSectionHeaders => 'En-têtes de requête';

  @override
  String get webReverseSignatureDiffSectionBody => 'Champs JSON du corps';

  @override
  String get webReverseSignatureDiffReportTitle =>
      'Analyse des champs de signature';

  @override
  String get webReverseSignatureDiffReportSamples => 'échantillons';

  @override
  String get webReverseSignatureDiffReportCopied =>
      'Rapport copié dans le presse-papiers';

  @override
  String get webReverseCoverageStartFailed => 'échec du démarrage';

  @override
  String get webReverseCoverageCollecting => 'Collecte en cours…';

  @override
  String get webReverseCoverageTakeFailed => 'échec d\'échantillonnage';

  @override
  String get webReverseCoverageStopped => 'Arrêté';

  @override
  String get webReverseCoverageReportCopied => 'Rapport copié';

  @override
  String get webReverseCoverageTitle => 'Couverture JS';

  @override
  String get webReverseCoverageSubtitle =>
      'Démarrer → utiliser la page → échantillonner pour voir quels scripts ont été exécutés';

  @override
  String get webReverseCoverageRecording => 'ENREGISTREMENT';

  @override
  String get webReverseCoverageStart => 'Démarrer';

  @override
  String get webReverseCoverageTake => 'Échantillon';

  @override
  String get webReverseCoverageStop => 'Arrêter';

  @override
  String get webReverseCoverageFilterHint => 'Filtrer par URL';

  @override
  String get webReverseCoverageCopyReport => 'Copier le rapport';

  @override
  String get webReverseCoverageNoData =>
      'Aucune donnée. Start → utilisez la page → Take.';

  @override
  String get webReverseCoverageClose => 'Fermer';

  @override
  String get webReverseCoverageCopyUrl => 'Copier l\'URL';

  @override
  String get webReverseCoverageCopied => 'Copié';

  @override
  String webReverseCoverageSampledCount(int count) {
    return '$count scripts échantillonnés';
  }

  @override
  String get webReverseDeviceEmuTitle => 'Émulation d\'appareil';

  @override
  String get webReverseDeviceEmuPresets => 'Préréglages';

  @override
  String get webReverseDeviceEmuCustom => 'Personnalisé';

  @override
  String get webReverseDeviceEmuWidth => 'Largeur';

  @override
  String get webReverseDeviceEmuHeight => 'Hauteur';

  @override
  String get webReverseDeviceEmuMobileMode => 'Mobile (touch + meta viewport)';

  @override
  String get webReverseDeviceEmuUaHint =>
      'Laisser vide pour conserver l\'UA par défaut';

  @override
  String get webReverseDeviceEmuApplyCustom => 'Appliquer personnalisé';

  @override
  String get webReverseDeviceEmuReset => 'Réinitialiser';

  @override
  String get webReverseDeviceEmuClose => 'Fermer';

  @override
  String get webReverseDeviceEmuMinSize => 'Taille minimale 100×100';

  @override
  String get webReverseDeviceEmuResetDone => 'Réinitialisé par défaut';

  @override
  String get webReverseDeviceEmuApplied => 'Appliqué';

  @override
  String get webReverseDeviceEmuClearingOverrides =>
      'Suppression des remplacements…';

  @override
  String get webReverseDeviceEmuApplyingCustom =>
      'Application des métriques personnalisées…';

  @override
  String webReverseDeviceEmuApplyingPreset(String label) {
    return 'Application de $label…';
  }

  @override
  String webReverseDeviceEmuAppliedPreset(String label) {
    return '$label appliqué';
  }

  @override
  String webReverseDeviceEmuAppliedCustomSize(int w, int h, String dpr) {
    return '$w×$h @ ${dpr}x appliqué';
  }

  @override
  String get webReverseWatchCopiedJson => 'JSON copié';

  @override
  String get webReverseWatchTitle => 'Expressions surveillées';

  @override
  String get webReverseWatchExportJson => 'Exporter JSON';

  @override
  String get webReverseWatchPause => 'Pause';

  @override
  String get webReverseWatchResume => 'Reprendre';

  @override
  String get webReverseWatchNoExpressions => 'Aucune expression';

  @override
  String get webReverseWatchAwaiting => 'en attente…';

  @override
  String get webReverseWatchDelete => 'Supprimer';

  @override
  String get webReverseWatchNameLabel => 'Nom (facultatif)';

  @override
  String get webReverseWatchExpressionLabel => 'Expression JS';

  @override
  String get webReverseWatchAddWatch => 'Ajouter une surveillance';

  @override
  String get webReverseWatchPickWatch => 'Choisissez à gauche';

  @override
  String get webReverseWatchClose => 'Fermer';

  @override
  String get webReverseWatchInterval => 'Intervalle';

  @override
  String get webReverseWatchNewestFirst => 'plus récent en premier';

  @override
  String get webReverseWatchAwaitingFirst =>
      'en attente de la première évaluation…';

  @override
  String webReverseWatchSubtitleHint(int ms, int count) {
    return 'Exécute Runtime.evaluate toutes les ${ms}ms, garde $count échantillons';
  }

  @override
  String webReverseWatchHistory(int count) {
    return 'Historique ($count)';
  }

  @override
  String get webReverseAccountSnapTitle => 'Instantanés de compte';

  @override
  String get webReverseAccountSnapSubtitle =>
      'Enregistrer cookies + localStorage/sessionStorage ; basculer entre comptes en un clic';

  @override
  String get webReverseAccountSnapNameLabel => 'Nom du compte actuel';

  @override
  String get webReverseAccountSnapNameHint => 'ex. main / test-001';

  @override
  String get webReverseAccountSnapCapture => 'Capturer';

  @override
  String get webReverseAccountSnapExportAll => 'Tout exporter';

  @override
  String get webReverseAccountSnapImport => 'Importer';

  @override
  String get webReverseAccountSnapClose => 'Fermer';

  @override
  String get webReverseAccountSnapEmptyHint =>
      'Aucun instantané. Saisissez un nom ci-dessus → cliquez sur « Capturer ».';

  @override
  String get webReverseAccountSnapApply => 'Appliquer';

  @override
  String get webReverseAccountSnapDelete => 'Supprimer';

  @override
  String get webReverseAccountSnapApplyFailedNoCdp =>
      'Échec de l\'application : pas de session CDP';

  @override
  String get webReverseAccountSnapNotSnapshotJson =>
      'Le presse-papiers n\'est pas un JSON d\'instantané';

  @override
  String webReverseAccountSnapSavedSnapshot(String name, int count) {
    return '« $name » enregistré ($count cookies)';
  }

  @override
  String webReverseAccountSnapAppliedSnapshot(String name) {
    return '« $name » appliqué. Actualisez la page pour que JS le relise.';
  }

  @override
  String webReverseAccountSnapCopiedCount(int count) {
    return '$count instantanés JSON copiés dans le presse-papiers';
  }

  @override
  String webReverseAccountSnapImportedCount(int count) {
    return '$count instantanés importés';
  }

  @override
  String webReverseAccountSnapSnapshotsCount(int count) {
    return '$count au total';
  }

  @override
  String get webReverseReqBpNewBreakpoint => 'Nouveau point d\'arrêt';

  @override
  String get webReverseReqBpTitle => 'Points d\'arrêt de requête';

  @override
  String get webReverseReqBpSubtitle =>
      'Correspondance par sous-chaîne URL/Body → journal + éval JS facultative. Activez d\'abord « Intercept ».';

  @override
  String get webReverseReqBpInterceptOff => 'Intercept OFF';

  @override
  String get webReverseReqBpAdd => 'Ajouter';

  @override
  String get webReverseReqBpEmptyHint =>
      'Cliquez sur + en haut à droite pour créer votre premier point d\'arrêt';

  @override
  String get webReverseReqBpUnnamed => '(sans nom)';

  @override
  String get webReverseReqBpPickHint =>
      'Sélectionnez un point d\'arrêt à gauche pour le modifier';

  @override
  String get webReverseReqBpClear => 'Effacer';

  @override
  String get webReverseReqBpNoHits => 'Aucun déclenchement';

  @override
  String get webReverseReqBpNameField => 'Nom';

  @override
  String get webReverseReqBpAnyMethod => 'Toutes';

  @override
  String get webReverseReqBpUrlContains => 'L\'URL contient';

  @override
  String get webReverseReqBpBodyContains => 'Le corps contient';

  @override
  String get webReverseReqBpEvalOnHit =>
      'Exécuter au déclenchement (facultatif)';

  @override
  String get webReverseReqBpEvalHint =>
      'ex. debugger; ou console.trace(\"hit\", new Error().stack)';

  @override
  String get webReverseReqBpDeleteBreakpoint => 'Supprimer ce point d\'arrêt';

  @override
  String webReverseReqBpHitsCount(int count) {
    return 'Déclenchements (récents $count)';
  }

  @override
  String get webReverseWsInjectTitle => 'Injection WebSocket';

  @override
  String get webReverseWsInjectSubtitle =>
      'Tous les WebSockets de la page passent par proxy → choisir la cible → injecter un frame texte';

  @override
  String get webReverseWsInjectProxyOn => 'PROXY ACTIF';

  @override
  String get webReverseWsInjectInstallFailed => 'Échec d\'installation';

  @override
  String get webReverseWsInjectRefresh => 'Actualiser';

  @override
  String get webReverseWsInjectNoLive =>
      'Aucun WebSocket actif.\nRechargez la page pour laisser le proxy intercepter les nouvelles connexions.';

  @override
  String get webReverseWsInjectPayloadLabel => 'Frame texte / JSON à envoyer';

  @override
  String get webReverseWsInjectPaste => 'Coller';

  @override
  String get webReverseWsInjectPickTarget => 'Choisir une cible';

  @override
  String get webReverseWsInjectTargetLabel => 'Cible';

  @override
  String get webReverseWsInjectLogEmpty =>
      'Le journal d\'injection apparaîtra ici';

  @override
  String get webReverseWsInjectClose => 'Fermer';

  @override
  String get webReverseWsInjectSend => 'Envoyer';

  @override
  String get webReverseWsInjectInjected => 'Injecté';

  @override
  String get webReverseWsInjectInjectFailed => 'Échec d\'injection';

  @override
  String webReverseWsInjectLiveCount(int count) {
    return '$count WebSocket(s) actif(s)';
  }

  @override
  String webReverseWsInjectSentBytes(int count) {
    return '$count octets envoyés';
  }

  @override
  String webReverseWsInjectFailedReason(String reason) {
    return 'Échec : $reason';
  }

  @override
  String get webReversePmTitle => 'Trace postMessage';

  @override
  String get webReversePmSubtitle =>
      'Injecter hook → tampon → drain toutes les 800 ms (iframe incluse)';

  @override
  String get webReversePmHookInjected => 'Hook postMessage injecté';

  @override
  String get webReversePmHookStopped =>
      'Arrêté (déhookage complet après rechargement)';

  @override
  String get webReversePmStop => 'Arrêter';

  @override
  String get webReversePmInject => 'Injecter';

  @override
  String get webReversePmClear => 'Effacer';

  @override
  String get webReversePmCopyJson => 'Copier JSON';

  @override
  String get webReversePmFilterHint => 'filtre par sous-chaîne';

  @override
  String get webReversePmChipSend => 'Envoyer';

  @override
  String get webReversePmChipRecv => 'Recevoir';

  @override
  String get webReversePmWaiting => 'En attente de postMessage…';

  @override
  String get webReversePmClickToCapture =>
      'Cliquez sur « Injecter » pour commencer la capture';

  @override
  String get webReversePmTagSend => 'ENVOI';

  @override
  String get webReversePmTagRecv => 'RECEPT';

  @override
  String get webReversePmClose => 'Fermer';

  @override
  String webReversePmCopiedCount(int count) {
    return '$count entrées copiées';
  }

  @override
  String get webReverseThrottleEnableNetwork =>
      'Activation du domaine Network…';

  @override
  String get webReverseThrottleApplyFailed => 'Échec d\'application';

  @override
  String get webReverseThrottleConditionsApplied =>
      'Conditions réseau appliquées';

  @override
  String get webReverseThrottleTitle => 'Simulation de conditions réseau';

  @override
  String get webReverseThrottleSubtitle =>
      'Network.emulateNetworkConditions : préréglages ou kbps/latence personnalisés';

  @override
  String get webReverseThrottlePresets => 'Préréglages';

  @override
  String get webReverseThrottleCustom => 'Personnalisé';

  @override
  String get webReverseThrottleDownKbps => 'Down kbps (0=∞)';

  @override
  String get webReverseThrottleUpKbps => 'Up kbps (0=∞)';

  @override
  String get webReverseThrottleLatencyMs => 'Latence ms';

  @override
  String get webReverseThrottleOffline => 'Hors ligne';

  @override
  String get webReverseThrottleDisableCache => 'Désactiver cache';

  @override
  String get webReverseThrottleApplyCustom => 'Appliquer';

  @override
  String get webReverseThrottleReset => 'Réinitialiser (sans throttle)';

  @override
  String get webReverseThrottleNotes => 'Notes';

  @override
  String get webReverseThrottleNotesBody =>
      '· Le throttle s\'applique à toute la session de la cible actuelle ; réinitialiser ou fermer pour restaurer.\n· kbps est converti en bytes/s via *1024/8 avant envoi ; hors ligne ignore le débit.\n· La désactivation du cache s\'applique à Fetch & Disk Cache, utile pour le cold-load.';

  @override
  String get webReverseThrottleClose => 'Fermer';

  @override
  String get webReverseThrottleUnknownError => 'inconnu';

  @override
  String webReverseThrottleStatusFailed(String reason) {
    return 'Échec : $reason';
  }

  @override
  String webReverseThrottleStatusApplied(String summary) {
    return 'Appliqué : $summary';
  }

  @override
  String get webReverseDomMutTitle => 'Enregistreur de mutations DOM';

  @override
  String get webReverseDomMutSubtitle =>
      'Injecte MutationObserver → chronologie en direct';

  @override
  String get webReverseDomMutRecordingStarted =>
      'Enregistrement des mutations DOM';

  @override
  String webReverseDomMutInstallFailed(String error) {
    return 'Échec de l\'installation : $error';
  }

  @override
  String webReverseDomMutCopiedRecords(int count) {
    return '$count entrées copiées';
  }

  @override
  String get webReverseDomMutExportJson => 'Exporter JSON';

  @override
  String get webReverseDomMutRecording => 'Enregistrement';

  @override
  String get webReverseDomMutStart => 'Démarrer';

  @override
  String get webReverseDomMutStop => 'Arrêter';

  @override
  String get webReverseDomMutClear => 'Effacer';

  @override
  String get webReverseDomMutFilterHint => 'Filtre (sous-chaîne)';

  @override
  String get webReverseDomMutAutoFollow => 'Suivi auto';

  @override
  String webReverseDomMutCounter(int count, int total) {
    return '$count / $total';
  }

  @override
  String get webReverseDomMutWaiting => 'En attente de mutations…';

  @override
  String get webReverseDomMutPressStart => 'Appuyer sur Démarrer';

  @override
  String get webReverseDomMutClose => 'Fermer';

  @override
  String get webReverseSmTitle => 'Résolveur SourceMap';

  @override
  String get webReverseSmSubtitle =>
      'min file:line:col → source originale:line:col';

  @override
  String get webReverseSmInvalidInput => 'saisie invalide';

  @override
  String get webReverseSmFetching => 'Récupération de la sourcemap...';

  @override
  String webReverseSmFetchFailed(String error) {
    return 'Échec de récupération : $error';
  }

  @override
  String get webReverseSmBadEvalResult => 'Résultat d\'évaluation invalide';

  @override
  String get webReverseSmNoMapping => 'Aucun segment de mappage';

  @override
  String get webReverseSmResolved => 'Résolu';

  @override
  String get webReverseSmCopied => 'Copié';

  @override
  String get webReverseSmUrlLabel => 'URL du fichier minifié';

  @override
  String get webReverseSmLineLabel => 'Ligne (basée sur 1)';

  @override
  String get webReverseSmColLabel => 'Colonne (basée sur 0)';

  @override
  String get webReverseSmResolve => 'Résoudre';

  @override
  String get webReverseSmEmptyHint =>
      'Entrez l\'URL + la position, puis résolvez';

  @override
  String get webReverseSmCopyTooltip => 'Copier';

  @override
  String get webReverseSmNameLabel => 'nom';

  @override
  String get webReverseSmClose => 'Fermer';

  @override
  String get webReverseCssCovStarting =>
      'Activation du domaine CSS et démarrage du suivi...';

  @override
  String webReverseCssCovStartFailed(String error) {
    return 'Échec du démarrage : $error';
  }

  @override
  String get webReverseCssCovTrackingActive =>
      'Suivi en cours — interagissez avec la page, puis cliquez « Arrêter et compter ».';

  @override
  String get webReverseCssCovStopping => 'Arrêt et agrégation en cours...';

  @override
  String webReverseCssCovStopFailed(String error) {
    return 'Échec de l\'arrêt : $error';
  }

  @override
  String webReverseCssCovResultsTallied(int sheets, int rules) {
    return '$sheets feuilles, $rules règles au total.';
  }

  @override
  String get webReverseCssCovJsonCopied => 'JSON copié';

  @override
  String get webReverseCssCovTitle => 'Couverture des règles CSS';

  @override
  String get webReverseCssCovSubtitle =>
      'CSS.startRuleUsageTracking · trouver les règles inutilisées';

  @override
  String get webReverseCssCovCopyJson => 'Copier le JSON';

  @override
  String get webReverseCssCovTracking => 'Suivi';

  @override
  String get webReverseCssCovIdle => 'Inactif';

  @override
  String get webReverseCssCovStopAndTally => 'Arrêter et compter';

  @override
  String get webReverseCssCovStartTracking => 'Démarrer le suivi';

  @override
  String get webReverseCssCovEmpty =>
      'Aucun résultat. Démarrez le suivi et interagissez avec la page.';

  @override
  String webReverseCssCovRuleStats(
    int used,
    int total,
    String usedKb,
    String totalKb,
  ) {
    return '$used/$total règles · $usedKb/$totalKb Ko';
  }

  @override
  String get webReverseCssCovClose => 'Fermer';

  @override
  String get webReverseAiCryptoStatusFetchResources =>
      'Récupération des ressources de la frame...';

  @override
  String get webReverseAiCryptoStatusDetecting =>
      'Détection des champs suspects...';

  @override
  String get webReverseAiCryptoStatusDone => 'Terminé';

  @override
  String get webReverseAiCryptoCopied => 'Copié dans le presse-papiers';

  @override
  String get webReverseAiCryptoTitle =>
      'Récupération des paramètres chiffrés IA';

  @override
  String get webReverseAiCryptoSubtitle =>
      'Grouper endpoint → diff variables → localiser dans JS → copier le prompt';

  @override
  String get webReverseAiCryptoRefresh => 'Réagréger';

  @override
  String get webReverseAiCryptoEmpty =>
      'Aucun endpoint analysable (≥2 hits par endpoint requis)';

  @override
  String get webReverseAiCryptoAnalyze => 'Analyser';

  @override
  String get webReverseAiCryptoCopyPrompt => 'Copier le prompt';

  @override
  String get webReverseAiCryptoSuspectsLabel => 'Champs suspects :';

  @override
  String get webReverseAiCryptoPromptHint =>
      'Cliquez sur Analyser pour générer le prompt.';

  @override
  String get webReverseAiCryptoClose => 'Fermer';

  @override
  String webReverseAiCryptoStatusSearchProgress(int done, int total) {
    return 'Recherche $done/$total';
  }

  @override
  String webReverseAiCryptoHits(int count) {
    return '$count hits';
  }

  @override
  String get webReverseCdpSendFailed => 'Échec de l\'envoi';

  @override
  String get webReverseCdpCopied => 'Copié';

  @override
  String get webReverseCdpTitle => 'Console CDP brute';

  @override
  String get webReverseCdpMethodLabel => 'method (Domain.command)';

  @override
  String get webReverseCdpUseSession => 'Utiliser page session';

  @override
  String get webReverseCdpSend => 'Envoyer';

  @override
  String get webReverseCdpNoHistory => 'Aucun historique';

  @override
  String get webReverseCdpSendHint =>
      'Envoyer une commande pour voir la réponse';

  @override
  String get webReverseCdpClose => 'Fermer';

  @override
  String get webReverseCdpCopyResponse => 'Copier la réponse';

  @override
  String get webReverseCdpParams => 'Paramètres';

  @override
  String get webReverseCdpResponse => 'Réponse';

  @override
  String get webReverseCdpError => 'Erreur';

  @override
  String webReverseCdpInvalidJson(String error) {
    return 'JSON invalide : $error';
  }

  @override
  String webReverseCdpSubtitle(int count) {
    return '⌘/Ctrl+Enter envoyer · Ctrl+↑/↓ historique · $count entrées';
  }

  @override
  String get webReversePerfTitle => 'Performance Trace';

  @override
  String get webReversePerfSubtitle => 'Tracing → chrome-trace JSON';

  @override
  String get webReversePerfDuration => 'Durée';

  @override
  String get webReversePerfCategories => 'Catégories Trace';

  @override
  String get webReversePerfCopyPath => 'Copier le chemin';

  @override
  String get webReversePerfStop => 'Arrêter';

  @override
  String get webReversePerfStart => 'Démarrer';

  @override
  String get webReversePerfClose => 'Fermer';

  @override
  String get webReversePerfTraceFailed => 'Échec du trace ou vide';

  @override
  String get webReversePerfStopping => 'Arrêt, finalisation…';

  @override
  String get webReversePerfTraceSaved => 'Trace enregistré';

  @override
  String get webReversePerfPathCopied => 'Chemin copié';

  @override
  String webReversePerfRecording(int seconds) {
    return 'Enregistrement (${seconds}s restants)';
  }

  @override
  String webReversePerfSaved(String path, String kb) {
    return 'Enregistré : $path ($kb KB)';
  }

  @override
  String get webReverseReplayJsonCopied => 'JSON copié';

  @override
  String get webReverseReplayTitle => 'Replay réseau en lot';

  @override
  String get webReverseReplaySubtitle =>
      'Multi-sélection → rejeu séquentiel → diff';

  @override
  String get webReverseReplayCopyResultsJson => 'Copier le JSON des résultats';

  @override
  String get webReverseReplayFilterByUrl => 'Filtrer par URL';

  @override
  String get webReverseReplaySelectAll => 'Tout sélectionner';

  @override
  String get webReverseReplayClear => 'Effacer';

  @override
  String get webReverseReplayEmpty => 'Aucune requête HTTP dans la session';

  @override
  String get webReverseReplayRunBatch => 'Lancer le lot';

  @override
  String get webReverseReplayClose => 'Fermer';

  @override
  String webReverseReplayDone(int ok, int total) {
    return 'Replay terminé : $ok/$total ok';
  }

  @override
  String webReverseReplayProgress(int done, int total) {
    return 'Rejeu $done / $total';
  }

  @override
  String webReverseReplaySelected(int count, int total) {
    return 'Sélectionné $count / $total';
  }

  @override
  String get webReverseGeoOverridesApplied => 'Surcharges appliquées';

  @override
  String get webReverseGeoEnvOverridesApplied =>
      'Surcharges d\'environnement appliquées';

  @override
  String get webReverseGeoOverridesCleared => 'Surcharges effacées';

  @override
  String get webReverseGeoEnvOverridesCleared =>
      'Surcharges d\'environnement effacées';

  @override
  String get webReverseGeoTitle => 'Geo / TZ / Locale Override';

  @override
  String get webReverseGeoCityPresets => 'Préréglages de ville';

  @override
  String get webReverseGeoEnableGeo =>
      'Activer la surcharge de géolocalisation';

  @override
  String get webReverseGeoEnableTz => 'Activer la surcharge de fuseau';

  @override
  String get webReverseGeoEnableLocale => 'Activer la surcharge de locale';

  @override
  String get webReverseGeoTip =>
      'Astuce : les surcharges s\'appliquent immédiatement sur la cible actuelle et persistent après rechargement. Inspecter via navigator.geolocation, Intl.DateTimeFormat().resolvedOptions().timeZone, navigator.language. Recharger fortement si le site met la détection en cache.';

  @override
  String get webReverseGeoClear => 'Effacer';

  @override
  String get webReverseGeoWorking => 'En cours…';

  @override
  String get webReverseGeoApply => 'Appliquer les surcharges';

  @override
  String get webReverseCollectionExportNothing => 'Rien à exporter';

  @override
  String get webReverseCollectionExportTitle => 'Exporter la collection API';

  @override
  String get webReverseCollectionExportSubtitle =>
      'Postman / Insomnia / Bruno / cURL / HAR — copier dans le presse-papiers';

  @override
  String get webReverseCollectionExportName => 'Nom de la collection';

  @override
  String get webReverseCollectionExportUrlFilter => 'Filtre URL';

  @override
  String get webReverseCollectionExportXhrOnly => 'XHR/Fetch uniquement';

  @override
  String get webReverseCollectionExportPreview2 =>
      'Aperçu : 2 premières entrées';

  @override
  String get webReverseCollectionExportClose => 'Fermer';

  @override
  String get webReverseCollectionExportCopyAction => 'Copier la collection';

  @override
  String get webReverseCollectionExportNoMatch =>
      '// Aucune requête correspondante.\n// Ajuster le filtre ou désactiver « XHR/Fetch uniquement ».';

  @override
  String webReverseCollectionExportCopied(int count) {
    return '$count requêtes copiées dans le presse-papiers';
  }

  @override
  String webReverseCollectionExportMatchCount(int match, int total) {
    return '$match correspondance · $total au total';
  }

  @override
  String get webReverseJwtTitle => 'Renouvellement JWT auto';

  @override
  String get webReverseJwtSubtitle =>
      'Scanner les JWT dans cookies/storage, exécuter le JS de refresh à l\'approche de l\'expiration';

  @override
  String get webReverseJwtScanNow => 'Scanner maintenant';

  @override
  String get webReverseJwtRefreshNow => 'Rafraîchir maintenant';

  @override
  String get webReverseJwtAuto => 'Auto';

  @override
  String get webReverseJwtIntervalSec => 'Intervalle(s)';

  @override
  String get webReverseJwtThresholdSec => 'Seuil(s)';

  @override
  String get webReverseJwtRefreshExpr => 'Expression de refresh (JS async)';

  @override
  String get webReverseJwtNoneFound => 'Aucun JWT trouvé';

  @override
  String get webReverseJwtRefreshLog => 'Journal de refresh';

  @override
  String get webReverseJwtClose => 'Fermer';

  @override
  String webReverseJwtFoundCount(int count) {
    return 'JWT trouvés ($count)';
  }

  @override
  String get webReverseWebauthnTitle => 'Authenticator virtuel WebAuthn';

  @override
  String get webReverseWebauthnDisabledBody =>
      'Activez WebAuthn via le commutateur en haut à droite pour créer des authenticators virtuels ; navigator.credentials.create/get fonctionnera sans clé matérielle.';

  @override
  String get webReverseWebauthnAdd => 'Ajouter un authenticator virtuel';

  @override
  String get webReverseWebauthnAddBtn => 'Ajouter';

  @override
  String get webReverseWebauthnNone => 'Aucun authenticator pour l\'instant';

  @override
  String get webReverseWebauthnClose => 'Fermer';

  @override
  String get webReverseWebauthnRefreshCreds => 'Rafraîchir les credentials';

  @override
  String get webReverseWebauthnRemove => 'Supprimer';

  @override
  String get webReverseWebauthnUserVerified => 'Utilisateur vérifié';

  @override
  String webReverseWebauthnAdded(String id) {
    return 'Authenticator $id ajouté';
  }

  @override
  String webReverseWebauthnCreatedCount(int count) {
    return 'Créés ($count)';
  }

  @override
  String webReverseWebauthnCredentialsCount(int count) {
    return 'Credentials ($count)';
  }

  @override
  String get webReverseInstallTitle => 'Google Chrome requis';

  @override
  String get webReverseInstallClose => 'Fermer';

  @override
  String get webReverseInstallBody =>
      'Web Reverse Expert nécessite un navigateur Chromium externe (Chrome / Edge / Brave / Chromium) piloté via CDP. Aucun n\'a été détecté.';

  @override
  String get webReverseInstallOpen => 'Ouvrir dans le navigateur';

  @override
  String get webReverseInstallHint =>
      'Installez Chrome puis réessayez. Si Edge / Brave / Chromium est déjà installé, cliquez sur «Déjà installé, revérifier».';

  @override
  String get webReverseInstallInstalled => 'Déjà installé';

  @override
  String get webReverseProfileEmptyPath => 'Chemin du profil vide; rien fait';

  @override
  String get webReverseProfileNoResidual =>
      'Aucun verrou résiduel. Si le lancement échoue, voir les autres causes dans le diagnostic.';

  @override
  String get webReverseProfileResetTitle =>
      'Verrous toujours présents — réinitialiser le profil ?';

  @override
  String get webReverseProfileResetConfirm => 'Réinitialiser';

  @override
  String get webReverseProfileKept =>
      'Profil conservé ; les verrous peuvent encore bloquer le prochain lancement.';

  @override
  String webReverseProfileCleanFailed(String error) {
    return 'Échec du nettoyage : $error';
  }

  @override
  String webReverseProfileCleaned(int count) {
    return '$count fichier(s) de verrou supprimé(s) ; profil sain';
  }

  @override
  String webReverseProfileResetBody(String path) {
    return 'Résidus SingletonLock nettoyés, mais verrous toujours présents.\n\nContinuer supprimera récursivement :\n$path\n\nLes Cookies / Login Data / extensions / historique sous ce profil seront perdus ; un nouveau profil sera recréé au prochain lancement.';
  }

  @override
  String webReverseProfileResetDone(String path) {
    return 'Profil réinitialisé : $path (60s de pause)';
  }

  @override
  String webReverseProfileResetFailed(String error) {
    return 'Échec de la réinitialisation : $error';
  }

  @override
  String get webReverseReplNoResult => '(aucun résultat)';

  @override
  String get webReverseReplCopied => 'Copié';

  @override
  String get webReverseReplTitle => 'Console REPL';

  @override
  String get webReverseReplSubtitle =>
      'Runtime.evaluate · ↑/↓ historique · Ctrl/⌘+Entrée exécuter';

  @override
  String get webReverseReplClear => 'Effacer le journal';

  @override
  String get webReverseReplEmpty =>
      'Saisir du JS ci-dessous → Ctrl/⌘+Entrée exécuter';

  @override
  String get webReverseReplHint =>
      'ex. : document.title ou await fetch(\"/api\").then(r=>r.json())';

  @override
  String get webReverseReplRun => 'Exécuter';

  @override
  String get webReverseConsoleEvalFailed => 'Échec de l\'évaluation';

  @override
  String get webReverseConsoleEmpty => 'Aucune sortie console pour le moment.';

  @override
  String get webReverseConsolePausedHint =>
      'Débogueur en pause · les expressions sont évaluées dans la portée de la frame supérieure';

  @override
  String get webReverseConsoleReplHint => 'Expression JS ; ↑↓ historique';

  @override
  String get webReverseConsoleClusterCopied => 'JSON du cluster copié';

  @override
  String get webReverseConsoleClusterTitle => 'Clusters de console';

  @override
  String get webReverseConsoleClusterRefresh => 'Actualiser';

  @override
  String get webReverseConsoleClusterFilterHint => 'filtre';

  @override
  String get webReverseConsoleClusterNoMatch => 'Aucune entrée correspondante';

  @override
  String get webReverseConsoleClusterCopyJson => 'Copier JSON';

  @override
  String webReverseConsoleClusterSubtitle(int entries, int clusters) {
    return 'déduplication par niveau + première ligne normalisée · $entries entrées / $clusters clusters';
  }

  @override
  String webReverseConsoleClusterTimes(String first, String last) {
    return 'première : $first\ndernière : $last';
  }

  @override
  String webReverseConsoleClusterMore(int count) {
    return '… et $count de plus';
  }

  @override
  String get webReverseDomSearchTitle => 'Recherche par sélecteur DOM';

  @override
  String get webReverseDomSearchSearching => 'Recherche…';

  @override
  String get webReverseDomSearchNoMatches => 'Aucun résultat';

  @override
  String get webReverseDomSearchHint =>
      'sélecteur / texte / XPath, Entrée pour exécuter';

  @override
  String get webReverseDomSearchRun => 'Exécuter';

  @override
  String get webReverseDomSearchExample =>
      'ex. : button[data-action] · #login · //a[contains(@href,\"docs\")]';

  @override
  String get webReverseDomSearchHighlight => 'Mettre en évidence sur la page';

  @override
  String webReverseDomSearchFailed(String error) {
    return 'Échec : $error';
  }

  @override
  String webReverseDomSearchGetFailed(String error) {
    return 'Échec de la récupération : $error';
  }

  @override
  String webReverseDomSearchHitCount(int total, int shown) {
    return '$total correspondances, $shown affichées';
  }

  @override
  String get webReverseFrameTreeTitle => 'Arborescence des frames';

  @override
  String get webReverseFrameTreeSubtitle =>
      'Page.getFrameTree · principal + iframes imbriqués';

  @override
  String get webReverseFrameTreeRefresh => 'Actualiser';

  @override
  String get webReverseFrameTreeCopyJson => 'Copier JSON';

  @override
  String get webReverseFrameTreeCopied => 'Copié';

  @override
  String get webReverseFrameTreeEmpty => 'Aucun frame';

  @override
  String webReverseFrameTreeFailed(String error) {
    return 'Échec : $error';
  }

  @override
  String webReverseFrameTreeCount(int count) {
    return '$count frames';
  }

  @override
  String get webReverseCpuThrottleOff => 'Limitation CPU désactivée';

  @override
  String get webReverseCpuThrottleResetDone => 'Réinitialisé';

  @override
  String get webReverseCpuThrottleTitle => 'Limitation CPU';

  @override
  String get webReverseCpuThrottlePresets => 'Préréglages';

  @override
  String get webReverseCpuThrottleNote =>
      'La limitation reste active après fermeture. Choisissez 1× (off) ou « Réinitialiser ».';

  @override
  String get webReverseCpuThrottleReset => 'Réinitialiser (1×)';

  @override
  String webReverseCpuThrottleApplying(String rate) {
    return 'Limitation CPU $rate× en cours...';
  }

  @override
  String webReverseCpuThrottleFailed(String error) {
    return 'Échec : $error';
  }

  @override
  String webReverseCpuThrottleCurrent(String rate) {
    return 'CPU limité $rate×';
  }

  @override
  String webReverseCpuThrottleSliderLabel(String rate) {
    return 'Curseur $rate×';
  }

  @override
  String webReverseCpuThrottleApplied(String rate) {
    return 'Limitation $rate× appliquée';
  }

  @override
  String get webReverseHeapTaking =>
      'Capture du heap snapshot en cours (peut prendre quelques secondes)...';

  @override
  String get webReverseHeapFailed => 'Échec du snapshot ou vide';

  @override
  String get webReverseHeapSavedToast => 'Snapshot enregistré';

  @override
  String get webReverseHeapPathCopied => 'Chemin copié';

  @override
  String get webReverseHeapSubtitle =>
      'HeapProfiler.takeHeapSnapshot → .heapsnapshot (chargeable dans DevTools Memory)';

  @override
  String get webReverseHeapEmptyHint =>
      'Cliquez ci-dessous pour capturer le heap snapshot V8 de la page.\nLes grandes pages peuvent dépasser 50 Mo.';

  @override
  String get webReverseHeapCopyPath => 'Copier le chemin';

  @override
  String get webReverseHeapTake => 'Capturer le snapshot';

  @override
  String webReverseHeapSaved(String path, String mb) {
    return 'Enregistré : $path ($mb Mo)';
  }

  @override
  String get webReverseRealtimeDirSent => 'Envoyé';

  @override
  String get webReverseRealtimeDirRecv => 'Reçu';

  @override
  String get webReverseRealtimeDirError => 'Erreur';

  @override
  String get webReverseRealtimePayloadCopied => 'Charge utile copiée';

  @override
  String get webReverseRealtimeTitle => 'Temps réel';

  @override
  String get webReverseRealtimeEmpty =>
      'Aucun WebSocket / EventSource pour l\'instant.\nUne action déclenchera une mise à jour en temps réel.';

  @override
  String get webReverseRealtimePickPrompt =>
      'Sélectionnez une connexion à gauche pour voir les trames.';

  @override
  String get webReverseRealtimeFilterHint =>
      'Filtrer la charge utile (sous-chaîne)';

  @override
  String get webReverseRealtimeAutoFollow => 'Suivi auto';

  @override
  String get webReverseRealtimeNoMatching => 'Aucune trame correspondante.';

  @override
  String webReverseRealtimeFrameCount(int count) {
    return '$count trames';
  }

  @override
  String get webReverseMarkupTitle => 'Annotation de capture';

  @override
  String get webReverseMarkupSaveWithout => 'Enregistrer sans annotation';

  @override
  String get webReverseMarkupExporting => 'Export en cours…';

  @override
  String get webReverseMarkupDone => 'Terminé';

  @override
  String get webReverseMarkupUndo => 'Annuler';

  @override
  String get webReverseMarkupClear => 'Effacer';

  @override
  String get webReverseMarkupAddTextTitle => 'Ajouter une étiquette texte';

  @override
  String get webReverseMarkupLabelHint => 'Saisir l\'étiquette';

  @override
  String get webReverseMarkupAdd => 'Ajouter';

  @override
  String get webReverseElementsLoadFailed =>
      'Échec de chargement : navigateur inactif ou CDP indisponible';

  @override
  String get webReverseElementsSelectorFailed =>
      'Échec de construction du sélecteur';

  @override
  String get webReverseElementsSelectorCopied => 'Sélecteur copié';

  @override
  String get webReverseElementsXPathFailed => 'Échec de construction de XPath';

  @override
  String get webReverseElementsXPathCopied => 'XPath copié';

  @override
  String get webReverseElementsReloadDom => 'Recharger la racine DOM';

  @override
  String get webReverseElementsCopySelector => 'Copier le sélecteur';

  @override
  String get webReverseElementsCopyXPath => 'Copier XPath';

  @override
  String get webReverseElementsScrollIntoView =>
      'Faire défiler jusqu\'à l\'élément';

  @override
  String get webReverseElementsPickElement =>
      'Sélectionner un élément dans l\'arbre';

  @override
  String get webReverseElementsNoAttrs => 'Aucun attribut';

  @override
  String get webReverseElementsNoComputed => 'Aucun style calculé';

  @override
  String get webReverseElementsNoListeners => 'Aucun écouteur d\'événement';

  @override
  String webReverseElementsAttrsTab(int count) {
    return 'Attrs ($count)';
  }

  @override
  String webReverseElementsComputedTab(int count) {
    return 'Calculé ($count)';
  }

  @override
  String webReverseElementsListenersTab(int count) {
    return 'Écouteurs ($count)';
  }

  @override
  String get webReverseCryptoSecEncode => 'Encodage';

  @override
  String get webReverseCryptoSecHash => 'Hachage';

  @override
  String get webReverseCryptoSecTime => 'Heure';

  @override
  String get webReverseCryptoClear => 'Effacer';

  @override
  String get webReverseCryptoInputHint => 'Coller ici…';

  @override
  String get webReverseCryptoInputLabel => 'Entrée';

  @override
  String get webReverseCryptoCopy => 'Copier';

  @override
  String get webReverseCryptoUseAsInput => 'Utiliser comme entrée';

  @override
  String get webReverseCryptoLengthLabel => 'Longueur';

  @override
  String get webReverseCryptoTsToIso => 'Horodatage → ISO';

  @override
  String get webReverseCryptoIsoToTs => 'ISO → Horodatage';

  @override
  String get webReverseCryptoNow => 'Maintenant';

  @override
  String get webReverseCryptoUuidHint =>
      'UUID v4 aléatoire (taper pour copier)';

  @override
  String get webReverseCryptoRegenerate => 'Régénérer';

  @override
  String webReverseCryptoCopied(String label) {
    return '$label copié';
  }

  @override
  String webReverseCryptoLengthValue(int chars, int bytes) {
    return 'car. $chars / octets $bytes';
  }

  @override
  String get webReverseHooksDefaultCode =>
      'S\'exécute avant chaque chargement du document ; patche window/fetch, etc.';

  @override
  String get webReverseHooksSavedToast => 'Enregistré et rechargé';

  @override
  String get webReverseHooksDeleteTitle => 'Supprimer le hook ?';

  @override
  String get webReverseHooksDeleteContent =>
      'Sera désinstallé immédiatement et de manière irréversible.';

  @override
  String get webReverseHooksDelete => 'Supprimer';

  @override
  String get webReverseHooksDiscardTitle =>
      'Abandonner les modifications non enregistrées ?';

  @override
  String get webReverseHooksKeepEditing => 'Continuer l\'édition';

  @override
  String get webReverseHooksDiscardConfirm => 'Abandonner';

  @override
  String get webReverseHooksLibrary => 'Bibliothèque de hooks';

  @override
  String get webReverseHooksNew => 'Nouveau hook';

  @override
  String get webReverseHooksEmpty =>
      'Aucun hook.\nAppuyez sur + pour en créer un.';

  @override
  String get webReverseHooksPickPrompt =>
      'Sélectionnez un hook à gauche ou créez-en un.';

  @override
  String get webReverseHooksNameLabel => 'Nom';

  @override
  String get webReverseHooksSave => 'Enregistrer (⌘S)';

  @override
  String get webReverseHooksSaved => 'Enregistré';

  @override
  String get webReverseHooksInfo =>
      'Enregistrer recharge instantanément. S\'exécute avant chaque chargement ; persiste après changement d\'onglet/recharge.';

  @override
  String webReverseHooksNewName(String time) {
    return 'hook $time';
  }

  @override
  String get webReverseSnippetsDefaultCode =>
      'Écrivez du JS ici. S\'exécute dans le contexte de la page.';

  @override
  String get webReverseSnippetsNoResult => '(aucun résultat)';

  @override
  String get webReverseSnippetsDeleteTitle => 'Supprimer le snippet ?';

  @override
  String get webReverseSnippetsDeleteContent =>
      'Cette action est irréversible.';

  @override
  String get webReverseSnippetsDelete => 'Supprimer';

  @override
  String get webReverseSnippetsTitle => 'Bloc de snippets';

  @override
  String get webReverseSnippetsNew => 'Nouveau snippet';

  @override
  String get webReverseSnippetsEmpty =>
      'Aucun snippet.\nAppuyez sur + pour en créer un.';

  @override
  String get webReverseSnippetsPickPrompt =>
      'Sélectionnez un snippet à gauche ou créez-en un.';

  @override
  String get webReverseSnippetsRun => 'Exécuter (⌘R)';

  @override
  String get webReverseSnippetsSaveDirty => 'Enregistrer *';

  @override
  String webReverseSnippetsNewName(String time) {
    return 'snippet $time';
  }

  @override
  String get servicesTitle => 'Services';

  @override
  String get servicesSubtitle =>
      'Accédez aux services professionnels développés par OpenHand pour une exécution stable, contrôlée et auditable.';

  @override
  String get servicesProprietaryBadge => 'Développé par OpenHand';

  @override
  String get servicesAiInfrastructureExposureScanTitle =>
      'Analyse de l’exposition de l’infrastructure IA';

  @override
  String get servicesAiInfrastructureExposureScanDescription =>
      'Détecte les services d’IA exposés dans un périmètre autorisé, identifie les identifiants divulgués et les configurations à risque, puis conserve des preuves d’intervention auditables.';

  @override
  String get agentsTitle => 'Agents';

  @override
  String get agentsSubtitle =>
      'Gérez les employés numériques Hermes Agent, leurs droits, tâches, clusters, audits et KPI.';

  @override
  String get agentsCreateAgent => 'Créer un agent';

  @override
  String get agentsEditAgent => 'Modifier l’agent';

  @override
  String get agentsLoadFailed => 'Échec du chargement des agents';

  @override
  String get agentsRetry => 'Réessayer';

  @override
  String get agentsEmptyTitle => 'Aucun agent';

  @override
  String get agentsEmptyBody =>
      'Utilisez Créer pour configurer le premier employé numérique avec périmètre, droits, tâches et gouvernance.';

  @override
  String get agentsMentorLabel => 'Mentor';

  @override
  String get agentsStopAgent => 'Arrêter l’agent';

  @override
  String get agentsStartAgent => 'Démarrer l’agent';

  @override
  String get agentsActivities => 'Activités';

  @override
  String get agentsLogs => 'Journaux';

  @override
  String get agentsCapabilityLogs => 'Journaux des capacités';

  @override
  String get agentsApprovals => 'Approbations';

  @override
  String get agentsCluster => 'Cluster';

  @override
  String get agentsMore => 'Plus';

  @override
  String get agentsTaskDesk => 'Table des tâches';

  @override
  String get agentsAuditReport => 'Rapport d’audit';

  @override
  String get agentsKpi => 'KPI';

  @override
  String get agentsResources => 'Ressources';

  @override
  String get agentsDeleteAgent => 'Supprimer l’agent';

  @override
  String agentsTasksCount(int running, int total) {
    return 'Tâches $running/$total';
  }

  @override
  String agentsApprovalsCount(int count) {
    return 'Approbations $count';
  }

  @override
  String agentsWorkersCount(int count, int max) {
    return 'Workers $count/$max';
  }

  @override
  String agentsCapabilitySkillsCount(int count) {
    return 'Compétences $count';
  }

  @override
  String agentsCapabilityKnowledgeCount(int count) {
    return 'Connaissances $count';
  }

  @override
  String agentsCapabilityMemoryCount(int count) {
    return 'Mémoire $count';
  }

  @override
  String agentsCapabilityToolsCount(int count) {
    return 'Outils $count';
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
  String get agentsSelfLearningOn => 'Auto-apprentissage activé';

  @override
  String get agentsNoCapabilityResources => 'Aucune ressource liée';

  @override
  String agentsDialogTitleWithName(String title, String name) {
    return '$title · $name';
  }

  @override
  String get agentsActivitiesEmptyTitle => 'Aucune activité.';

  @override
  String get agentsLogsEmptyTitle =>
      'Aucun journal Skill, Mémoire, MCP ou outil.';

  @override
  String get agentsApprovalsEmptyTitle => 'Aucune demande d’approbation.';

  @override
  String get agentsListEmptyBody =>
      'Les entrées apparaissent ici lorsque l’agent travaille.';

  @override
  String agentsMinWorkersCount(int count) {
    return 'Min $count';
  }

  @override
  String agentsMaxWorkersCount(int count) {
    return 'Max $count';
  }

  @override
  String get agentsNoWorkersTitle => 'Aucun worker';

  @override
  String get agentsNoWorkersBody =>
      'Les workers sont préparés selon la taille minimale configurée.';

  @override
  String agentsWorkerSubtitle(String status, int done, int priority) {
    return '$status · Terminé $done · Priorité $priority';
  }

  @override
  String get agentsPublishTask => 'Publier une tâche';

  @override
  String get agentsNoTasksTitle => 'Aucune tâche';

  @override
  String get agentsNoTasksBody =>
      'Publiez les tâches ici ; les workers les exécutent et renvoient les résultats.';

  @override
  String get agentsAuditRequests => 'Requêtes';

  @override
  String get agentsAuditCompleted => 'Terminées';

  @override
  String get agentsAuditUtilization => 'Utilisation';

  @override
  String get agentsRecentAuditEvents => 'Événements d’audit récents';

  @override
  String get agentsNoAuditData => 'Aucune donnée d’audit.';

  @override
  String get agentsNoKpiTitle => 'Aucun KPI';

  @override
  String get agentsNoKpiBody =>
      'Ajoutez des KPI dans l’éditeur pour guider la planification de l’agent.';

  @override
  String get agentsMetricMemory => 'Mémoire';

  @override
  String get agentsMetricDisk => 'Disque';

  @override
  String get agentsMetricPersisted => 'Persisté';

  @override
  String get agentsMetricHandles => 'Handles';

  @override
  String get agentsPublish => 'Publier';

  @override
  String get agentsTaskTitleLabel => 'Titre';

  @override
  String get agentsDescriptionLabel => 'Description';

  @override
  String get agentsContentLabel => 'Contenu';

  @override
  String get agentsNoteLabel => 'Note';

  @override
  String get agentsDeleteConfirmTitle => 'Supprimer l’agent';

  @override
  String agentsDeleteConfirmMessage(String name) {
    return 'Supprimer $name ? Les skills, connaissances et serveurs MCP liés sont conservés.';
  }

  @override
  String get agentsTabProfile => 'Profil';

  @override
  String get agentsTabCapabilities => 'Capacités';

  @override
  String get agentsTabRuntime => 'Exécution';

  @override
  String get agentsTabGovernance => 'Gouvernance';

  @override
  String get agentsTabMetadata => 'Métadonnées';

  @override
  String get agentsFieldAvatar => 'Avatar';

  @override
  String get agentsFieldAvatarHint => 'Texte, emoji ou image';

  @override
  String get agentsFieldNameRequired => 'Nom *';

  @override
  String get agentsFieldPosition => 'Poste';

  @override
  String get agentsFieldDepartment => 'Département';

  @override
  String get agentsFieldLevel => 'Niveau';

  @override
  String get agentsFieldIntroduction => 'Introduction';

  @override
  String get agentsFieldArchive => 'Archive';

  @override
  String get agentsFieldRouteFrontMatter => 'En-tête de routage';

  @override
  String get agentsFieldWelcomeMessage => 'Message d’accueil';

  @override
  String get agentsFieldPersona => 'Persona';

  @override
  String get agentsFieldResponsibilityBoundary => 'Périmètre de responsabilité';

  @override
  String get agentsKnowledgeBase => 'Base de connaissances';

  @override
  String get agentsBuiltInTools => 'Outils intégrés';

  @override
  String get agentsModelLabel => 'Modèle';

  @override
  String get agentsEnableAgentTitle => 'Activer l’agent';

  @override
  String get agentsEnableAgentBody =>
      'Active la boucle de l’agent et ses outils intégrés.';

  @override
  String get agentsSelfLearningTitle => 'Auto-apprentissage';

  @override
  String get agentsSelfLearningBody =>
      'Utilise Hermes Agent pour capitaliser skills, mémoire et expérience.';

  @override
  String get agentsFieldWorkspacePath => 'Chemin de travail';

  @override
  String get agentsFieldWorkspaceScope => 'Périmètre de travail';

  @override
  String get agentsCrons => 'Crons';

  @override
  String get agentsClusterScaling => 'Mise à l’échelle du cluster';

  @override
  String get agentsMinWorkersLabel => 'Workers min.';

  @override
  String get agentsMaxWorkersLabel => 'Workers max.';

  @override
  String get agentsMaxRetriesLabel => 'Réessais max.';

  @override
  String get agentsSchedulerPolicyLabel => 'Politique de planification';

  @override
  String get agentsTaskLabelsLabel => 'Étiquettes de tâche';

  @override
  String get agentsFieldName => 'Nom';

  @override
  String get agentsFieldTarget => 'Objectif';

  @override
  String get agentsMetadataInfoTitle => 'Métadonnées de droits et profil';

  @override
  String get agentsNoOptionsAvailable => 'Aucune option disponible.';

  @override
  String get agentExecutionModeNormal => 'Par défaut';

  @override
  String get agentExecutionModeFullAccess => 'Accès complet';

  @override
  String get agentLifecycleStopped => 'Arrêté';

  @override
  String get agentLifecycleRunning => 'En cours';

  @override
  String get agentLifecyclePaused => 'En pause';

  @override
  String get agentLifecycleDegraded => 'Dégradé';

  @override
  String get agentTaskStatusBacklog => 'Backlog';

  @override
  String get agentTaskStatusReady => 'Prêt';

  @override
  String get agentTaskStatusRunning => 'En cours';

  @override
  String get agentTaskStatusWaitingApproval => 'Approbation';

  @override
  String get agentTaskStatusPaused => 'En pause';

  @override
  String get agentTaskStatusCompleted => 'Terminée';

  @override
  String get agentTaskStatusFailed => 'Échec';

  @override
  String get agentTaskStatusCanceled => 'Annulée';

  @override
  String get agentApprovalStatusPending => 'En attente';

  @override
  String get agentApprovalStatusApproved => 'Approuvée';

  @override
  String get agentApprovalStatusRejected => 'Rejetée';

  @override
  String get agentApprovalStatusExpired => 'Expirée';

  @override
  String get agentWorkerStatusIdle => 'Inactif';

  @override
  String get agentWorkerStatusBusy => 'Occupé';

  @override
  String get agentWorkerStatusDraining => 'Drainage';

  @override
  String get agentWorkerStatusOffline => 'Hors ligne';

  @override
  String get agentsActivityAgentStarted => 'Agent démarré';

  @override
  String get agentsActivityAgentStopped => 'Agent arrêté';

  @override
  String get agentsActivityTaskPublished => 'Tâche publiée';

  @override
  String get agentsActivityTaskUpdated => 'Tâche mise à jour';

  @override
  String get agentsActivityTaskCanceled => 'Tâche annulée';

  @override
  String get agentsActivityTaskPaused => 'Tâche en pause';

  @override
  String get agentsActivityTaskTerminated => 'Tâche terminée';

  @override
  String get agentsActivityTaskResumed => 'Tâche reprise';

  @override
  String get hookEventSessionStart => 'Début de session';

  @override
  String get hookEventUserPromptSubmit => 'Soumission du prompt';

  @override
  String get hookEventPreToolUse => 'Avant outil';

  @override
  String get hookEventPostToolUse => 'Après outil';

  @override
  String get hookEventSubagentStart => 'Démarrage du sous-agent';

  @override
  String get hookEventSubagentStop => 'Arrêt du sous-agent';

  @override
  String get hookEventStop => 'Arrêt';

  @override
  String get hookEventPreCompact => 'Avant compactage';

  @override
  String get hookEventSessionEnd => 'Fin de session';

  @override
  String get hookEventErrorOccurred => 'Erreur survenue';

  @override
  String get builtinToolLoadStrategyEagerShort => 'Immédiat';

  @override
  String get builtinToolLoadStrategyLazy => 'Différé';

  @override
  String get builtinToolLoadStrategyDeferred => 'Reporté';

  @override
  String get builtinToolLoadStrategyEagerFull => 'Chargement immédiat';

  @override
  String get builtinToolCustomBadge => 'Personnalisé';

  @override
  String get builtinToolForceBadge => 'Forcer';

  @override
  String get builtinToolMoveUp => 'Monter';

  @override
  String get builtinToolMoveDown => 'Descendre';

  @override
  String builtinToolEditorTitle(String kind) {
    return 'Modifier l’outil — $kind';
  }

  @override
  String get builtinToolEnableTitle => 'Activer l’outil';

  @override
  String get builtinToolEnableBody =>
      'Désactivé, cet outil n’apparaît pas dans le catalogue du modèle.';

  @override
  String get builtinToolDisplayNameLabel => 'Nom affiché (facultatif)';

  @override
  String get builtinToolDisplayNameHelper =>
      'Remplace le nom par défaut. Laissez vide pour conserver la valeur intégrée.';

  @override
  String get builtinToolSummaryLabel => 'Résumé (facultatif)';

  @override
  String get builtinToolSummaryHelper =>
      'Affiché dans la liste des outils pour référence rapide.';

  @override
  String get builtinToolPromptOverrideLabel =>
      'Remplacement de prompt (facultatif)';

  @override
  String get builtinToolPromptOverrideHelper =>
      'Ajouté à la description de l’outil pour ajuster son usage par le modèle.';

  @override
  String get builtinToolSchemaOverrideLabel =>
      'Remplacement du schéma (JSON, facultatif)';

  @override
  String get builtinToolSchemaOverrideHelper =>
      'Objet JSON Schema complet remplaçant les paramètres d’entrée. Laissez vide par défaut.';

  @override
  String get builtinToolPriorityLabel => 'Priorité (0–9999)';

  @override
  String get builtinToolPriorityHelper => 'Plus petit = plus prioritaire';

  @override
  String get builtinToolLoadStrategyLabel => 'Stratégie de chargement';

  @override
  String get builtinToolForceLoadTitle => 'Forcer le chargement';

  @override
  String get builtinToolForceLoadBody =>
      'Activé, ce schéma est envoyé directement même si le lazy loading intégré est Auto ou activé.';

  @override
  String get builtinToolMaxOutputLabel => 'Sortie max. (caractères)';

  @override
  String get builtinToolGlobalDefaultHint => 'Défaut global';

  @override
  String get builtinToolTagsLabel => 'Tags (séparés par des virgules)';

  @override
  String get builtinToolTagsHelper => 'ex. io, file, dangerous';

  @override
  String get builtinToolRequireConfirmationTitle => 'Confirmation requise';

  @override
  String get builtinToolRequireConfirmationBody =>
      'Demande une confirmation avant exécution. « Par défaut » utilise le comportement intégré.';

  @override
  String get builtinToolConfirmationDefault => 'Par défaut';

  @override
  String get builtinToolConfirmationYes => 'Oui';

  @override
  String get builtinToolConfirmationNo => 'Non';

  @override
  String get memoryTitleField => 'Titre (facultatif)';

  @override
  String get memoryTitleHint =>
      'Résumez ce souvenir en une phrase ; laissez vide pour utiliser l’aperçu du contenu';

  @override
  String get commonRetry => 'Réessayer';

  @override
  String get commonOk => 'OK';

  @override
  String get commonExport => 'Exporter';

  @override
  String get appUpdateDialogTitle => 'Rechercher des mises à jour';

  @override
  String get appUpdateChecking => 'Recherche des mises à jour...';

  @override
  String appUpdateCurrentVersion(Object version) {
    return 'Version actuelle : $version';
  }

  @override
  String appUpdateNewVersion(Object version) {
    return 'Nouvelle version : v$version';
  }

  @override
  String appUpdatePublished(Object date) {
    return 'Publié : $date';
  }

  @override
  String appUpdateFileSize(Object size) {
    return 'Taille : $size';
  }

  @override
  String get appUpdateAlreadyLatestTitle => 'Vous êtes à jour';

  @override
  String appUpdateAlreadyLatestBody(Object version) {
    return 'OpenHand $version est la dernière version.';
  }

  @override
  String get appUpdateDownloadComplete => 'Téléchargement terminé';

  @override
  String get appUpdateDownloading => 'Téléchargement...';

  @override
  String get appUpdateCheckFailed => 'Échec de la recherche de mise à jour';

  @override
  String get appUpdateLater => 'Plus tard';

  @override
  String get appUpdateDownload => 'Télécharger';

  @override
  String get exportRangeInvalid =>
      'Saisissez une plage valide (1 ≤ début ≤ fin)';

  @override
  String get exportRangeStart => 'Début';

  @override
  String get exportRangeEnd => 'Fin';

  @override
  String get exportSessionSettingsTitle => 'Exporter les paramètres de session';

  @override
  String exportTotalMessages(Object count) {
    return 'Messages disponibles : $count';
  }

  @override
  String get exportRolesSection => 'Rôles';

  @override
  String get exportAllRoles => 'Tous les rôles';

  @override
  String get exportMessageKindsSection => 'Types de message';

  @override
  String get exportAllKinds => 'Tous les types';

  @override
  String get exportMessageRangeSection => 'Plage de messages';

  @override
  String get exportOnlyRange =>
      'Exporter uniquement une plage (base 1, incluse)';

  @override
  String get exportOtherOptions => 'Autres options';

  @override
  String get exportIncludeDeleted => 'Inclure les messages supprimés';

  @override
  String get exportPickOneRole => 'Sélectionnez au moins un rôle.';

  @override
  String get exportPickOneMessageKind =>
      'Sélectionnez au moins un type de message.';

  @override
  String get exportRoleSystem => 'Système';

  @override
  String get exportRoleUser => 'Utilisateur';

  @override
  String get exportRoleAssistant => 'Assistant';

  @override
  String get exportRoleTool => 'Outil';

  @override
  String get exportKindUser => 'Message utilisateur';

  @override
  String get exportKindAssistant => 'Réponse assistant';

  @override
  String get exportKindReasoning => 'Raisonnement';

  @override
  String get exportKindToolCall => 'Appel d’outil';

  @override
  String get exportKindTool => 'Résultat d’outil';

  @override
  String get exportKindCompressionPoint => 'Point de compression';

  @override
  String get exportKindMcp => 'Événement MCP';

  @override
  String get exportKindSkill => 'Événement de compétence';

  @override
  String get exportKindHook => 'Événement Hook';

  @override
  String get exportKindSelfLearning => 'Auto-apprentissage';

  @override
  String get exportKindFileMutationSummary =>
      'Résumé des changements de fichiers';

  @override
  String get exportKindStatus => 'Message d’état';

  @override
  String get exportPhaseLogRangeSection => 'Plage de logs de phase';

  @override
  String exportTotalPhaseLogs(Object count) {
    return 'Logs de phase disponibles : $count';
  }

  @override
  String get modelSearchHint => 'Rechercher des modèles…';

  @override
  String modelSearchResultCount(Object filtered, Object total) {
    return '$filtered / $total modèles';
  }

  @override
  String get modelSearchNoAvailableModels => 'Aucun modèle disponible';

  @override
  String get modelSearchNoMatchingModels => 'Aucun modèle correspondant';

  @override
  String get modelSearchRecent => 'Récents';

  @override
  String get nativeAudioLoadFailed =>
      'Impossible de charger l’audio. Ouvrez-le avec le lecteur système.';

  @override
  String get nativeAudioPlaybackFailed =>
      'Échec de la lecture. Réessayez ou ouvrez avec le lecteur système.';

  @override
  String get nativeAudioBack15Seconds => 'Reculer de 15 s';

  @override
  String get nativeAudioPause => 'Pause';

  @override
  String get nativeAudioPlay => 'Lire';

  @override
  String get nativeAudioForward15Seconds => 'Avancer de 15 s';

  @override
  String get nativeAudioMute => 'Muet';

  @override
  String get nativeAudioUnmute => 'Réactiver le son';

  @override
  String get nativeAudioSystemPlayer => 'Lecteur système';

  @override
  String get nativeAudioSequencePlayback => 'Lecture séquentielle';

  @override
  String get nativeAudioRepeatOne => 'Répéter un titre';

  @override
  String get nativeAudioShufflePlayback => 'Lecture aléatoire';

  @override
  String nativeAudioEffectTooltip(Object effect) {
    return 'Effet : $effect';
  }

  @override
  String get nativeAudioEffectStandard => 'Standard';

  @override
  String get nativeAudioEffectSpatial => '3D';

  @override
  String get nativeAudioEffectVocal => 'Voix';

  @override
  String get nativeAudioEffectWarm => 'Chaud';

  @override
  String get hooksTitle => 'Hooks';

  @override
  String get hooksSubtitle =>
      'Configurez les scripts à exécuter à chaque étape du cycle de vie de l’agent IA. Les Hooks s’exécutent dans l’ordre lorsque l’événement correspondant se déclenche.';

  @override
  String get hooksNew => 'Nouveau Hook';

  @override
  String get hooksDeleteTitle => 'Supprimer le Hook';

  @override
  String hooksDeleteMessage(Object label) {
    return 'Supprimer « $label » ? Cette action est irréversible.';
  }

  @override
  String get hooksEmptyTitle => 'Aucun Hook configuré';

  @override
  String get hooksEmptyBody =>
      'Cliquez sur « Nouveau Hook » ci-dessus pour commencer.';

  @override
  String get hooksTimeoutTooltip => 'Délai d’attente';

  @override
  String hooksInlineScriptDescription(Object firstLine) {
    return 'Inline : $firstLine';
  }

  @override
  String get hooksNoScriptConfigured => 'Aucun script configuré';

  @override
  String get hooksEditTitle => 'Modifier le Hook';

  @override
  String get hooksLabelField => 'Libellé';

  @override
  String get hooksLabelHint => 'ex. Journalisation';

  @override
  String get hooksTriggerEvent => 'Événement déclencheur';

  @override
  String get hooksScriptSource => 'Source du script';

  @override
  String get hooksScriptSourceFile => 'Fichier';

  @override
  String get hooksScriptSourceInline => 'Inline';

  @override
  String get hooksScriptFilePath => 'Chemin du script';

  @override
  String get hooksScriptFileHint => 'Sélectionnez un fichier .sh / .ps1 / .bat';

  @override
  String get hooksBrowse => 'Parcourir';

  @override
  String get hooksScriptContextFileHelp =>
      'Le JSON de contexte est transmis de deux façons sûres (toutes deux compatibles avec jq) :\n① Fichier temporaire : jq -r .session_id \"\$OPENHAND_HOOK_CONTEXT_FILE\"\n② Octets bruts stdin : jq -r .session_id\nChamps : session_id, session_file_path, environment, etc.';

  @override
  String get hooksInlineWindowsHint => 'Saisissez un script PowerShell / BAT';

  @override
  String get hooksInlineShellHint =>
      'Saisissez un script shell (#!/bin/bash non requis)';

  @override
  String get hooksScriptContextInlineHelp =>
      'Le JSON de contexte est transmis de deux façons sûres (toutes deux compatibles avec jq) :\n① Fichier temporaire : SID=\$(jq -r .session_id \"\$OPENHAND_HOOK_CONTEXT_FILE\")\n② Octets bruts stdin : SID=\$(jq -r .session_id)\nChamps : session_id, session_file_path, environment, statistics, etc.';

  @override
  String get hooksTimeoutSeconds => 'Délai d’attente (secondes)';

  @override
  String get hooksEnabled => 'Activé';

  @override
  String get hooksValidationLabelRequired => 'Saisissez un libellé de Hook.';

  @override
  String get hooksValidationScriptFileRequired =>
      'Sélectionnez un fichier de script.';

  @override
  String get hooksValidationInlineScriptRequired =>
      'Saisissez le contenu du script inline.';

  @override
  String get hooksFileTypeScripts => 'Scripts';

  @override
  String get hooksFileTypeShellScripts => 'Scripts shell';

  @override
  String get hooksFileTypeAllFiles => 'Tous les fichiers';

  @override
  String get commonConfirm => 'Confirmer';

  @override
  String get choiceInputCustomOptionLabel => 'Saisie personnalisée';

  @override
  String get choiceInputCustomInputHint => 'Saisissez votre réponse ici…';

  @override
  String get choiceInputCustomOptionDescription =>
      'Choisissez cette option pour saisir votre propre réponse';

  @override
  String get mediaPreviewImageCopied => 'Image copiée dans le presse-papiers.';

  @override
  String get mediaPreviewImageFileOrPathCopied =>
      'Fichier image ou chemin copié dans le presse-papiers.';

  @override
  String get mediaPreviewMediaFileCopied =>
      'Fichier média copié dans le presse-papiers.';

  @override
  String get mediaPreviewDirectCopyUnavailablePathCopied =>
      'La copie directe du fichier média n’est pas disponible sur cette plateforme. Chemin copié.';

  @override
  String get mediaPreviewMediaUrlCopied => 'URL du média copiée.';

  @override
  String get mediaPreviewDirectCopyUnavailableTempPathCopied =>
      'La copie directe du fichier média n’est pas disponible sur cette plateforme. Chemin temporaire copié.';

  @override
  String get mediaPreviewDataCopyFailedUrlCopied =>
      'Impossible de copier les données média. URL source copiée.';

  @override
  String mediaPreviewCopyFailed(Object error) {
    return 'Échec de la copie : $error';
  }

  @override
  String get mediaPreviewNoSource => 'La source média est indisponible.';

  @override
  String get knowledgeVectorDistributionTitle => 'Distribution des vecteurs';

  @override
  String get knowledgeVectorDistributionLoading =>
      'Échantillonnage et projection des vecteurs.';

  @override
  String get knowledgeVectorDistributionEmpty =>
      'La collection actuelle n’a aucun vecteur à afficher.';

  @override
  String get knowledgeVectorProjectionSection => 'Projection';

  @override
  String get knowledgeVectorAlgorithm => 'Algorithme';

  @override
  String get knowledgeVectorOriginalDimensions => 'Dimensions originales';

  @override
  String get knowledgeVectorVisiblePoints => 'Points visibles';

  @override
  String get knowledgeVectorSampled => 'Échantillonné';

  @override
  String get knowledgeVectorDurationMs => 'Durée (ms)';

  @override
  String get knowledgeVectorResample => 'Rééchantillonner';

  @override
  String get qdrantStatusRefreshIncomplete =>
      'L’actualisation de l’état Qdrant a renvoyé des données incomplètes.';

  @override
  String get qdrantStatusRawVectorEmpty => 'Saisissez d’abord un vecteur brut.';

  @override
  String qdrantStatusRawVectorInvalid(Object value) {
    return 'Nombre de vecteur invalide : $value';
  }

  @override
  String qdrantStatusRawVectorDimensionMismatch(int actual, int expected) {
    return 'Le vecteur brut a $actual dimensions ; la configuration actuelle en exige $expected.';
  }

  @override
  String get qdrantStatusPointIdsEmpty =>
      'Saisissez d’abord des ID de points/chunks.';

  @override
  String get qdrantStatusPayloadIndexesSubmitted =>
      'Création des index Payload par défaut envoyée.';

  @override
  String get qdrantStatusDangerousOpsDisabled =>
      'Activez d’abord les opérations d’administration dangereuses dans les réglages de la base de connaissances.';

  @override
  String get qdrantStatusDeletePointIdsEmpty =>
      'Saisissez d’abord les ID de points à supprimer.';

  @override
  String get qdrantStatusDeletePointsTitle => 'Supprimer les points Qdrant ?';

  @override
  String qdrantStatusDeletePointsMessage(int count) {
    return 'Supprime $count points de la collection actuelle. Cette action est irréversible.';
  }

  @override
  String get qdrantStatusDeletePointsConfirm => 'Supprimer les points';

  @override
  String get qdrantStatusPointsDeleted => 'Points supprimés.';

  @override
  String get qdrantStatusDeleteCollectionTitle =>
      'Supprimer la collection Qdrant ?';

  @override
  String qdrantStatusDeleteCollectionMessage(Object collection) {
    return 'Supprime la collection « $collection » et tous ses points. Cette action est irréversible.';
  }

  @override
  String get qdrantStatusDeleteCollectionConfirm => 'Supprimer la collection';

  @override
  String get qdrantStatusCollectionDeleted => 'Collection supprimée.';

  @override
  String get qdrantStatusDiagnosticsCopied => 'Diagnostics copiés.';

  @override
  String get qdrantStatusTitle => 'Opérations Qdrant';

  @override
  String get qdrantStatusTabOverview => 'Vue d’ensemble';

  @override
  String get qdrantStatusTabCollections => 'Collections';

  @override
  String get qdrantStatusTabPoints => 'Points';

  @override
  String get qdrantStatusTabDiagnostics => 'Diagnostics';

  @override
  String get qdrantStatusRefresh => 'Actualiser';

  @override
  String get qdrantStatusCopyDiagnostics => 'Copier les diagnostics';

  @override
  String get qdrantStatusHeaderTitle => 'État de la base vectorielle locale';

  @override
  String get qdrantStatusMetricCollections => 'Collections';

  @override
  String get qdrantStatusMetricPoints => 'Points';

  @override
  String get qdrantStatusMetricIndexedVectors => 'Vecteurs indexés';

  @override
  String get qdrantStatusMetricChunks => 'Chunks';

  @override
  String get qdrantStatusMetricPendingJobs => 'Tâches en attente';

  @override
  String get qdrantStatusMetricWalCapacity => 'Capacité WAL';

  @override
  String get qdrantStatusSmoothTrend => 'Tendance lissée';

  @override
  String get qdrantStatusNoCollections =>
      'Aucune collection trouvée, ou Qdrant est indisponible.';

  @override
  String get qdrantStatusPointsSectionTitle => 'Points / recherche / parcours';

  @override
  String get qdrantStatusPointIdsLabel => 'ID de points/chunks';

  @override
  String get qdrantStatusSourceFilterLabel => 'Filtre d’ID source';

  @override
  String get qdrantStatusTagFilterLabel => 'Filtre de tags';

  @override
  String get qdrantStatusLimitLabel => 'Limite';

  @override
  String get qdrantStatusRawVectorLabel =>
      'Vecteur brut (séparé par virgules ou espaces, dimensions identiques)';

  @override
  String get qdrantStatusQueryIds => 'Requête par ID';

  @override
  String get qdrantStatusScrollFilter => 'Parcourir / filtrer';

  @override
  String get qdrantStatusRawVectorSearch => 'Recherche par vecteur brut';

  @override
  String get qdrantStatusRebuildPayloadIndexes =>
      'Reconstruire les index Payload';

  @override
  String get qdrantStatusDeletePoints => 'Supprimer des points';

  @override
  String get qdrantStatusOperationResult => 'Résultat de l’opération';

  @override
  String get qdrantStatusRawDiagnosticsJson => 'JSON de diagnostic brut';

  @override
  String get qdrantStatusNoDiagnostics => 'Aucun diagnostic pour l’instant.';

  @override
  String get qdrantStatusLatestOperationResult =>
      'Dernier résultat d’opération';

  @override
  String get qdrantStatusOperationLog => 'Journal des opérations';

  @override
  String get qdrantStatusNoOperations => 'Aucune opération pour l’instant.';

  @override
  String get qdrantStatusCollectingSamples =>
      'Collecte d’échantillons pour la tendance.';

  @override
  String get qdrantStatusTrendPoints => 'points';

  @override
  String get qdrantStatusTrendChunks => 'chunks';

  @override
  String get qdrantStatusTrendPendingFailed => 'attente/échec';

  @override
  String qdrantStatusTrendSampleCount(int count) {
    return '$count points';
  }

  @override
  String get qdrantSectionOverview => 'Vue d’ensemble';

  @override
  String get qdrantSectionDockerContainer => 'Docker / conteneur';

  @override
  String get qdrantSectionApiMetrics => 'Métriques API Qdrant';

  @override
  String get qdrantSectionCollectionConfig => 'Configuration de collection';

  @override
  String get qdrantSectionStorageOptimizer => 'Stockage / optimiseur';

  @override
  String get qdrantSectionTelemetry => 'Télémétrie';

  @override
  String get qdrantSectionOpenHandKnowledge => 'Base de connaissances OpenHand';

  @override
  String get qdrantMetricServiceStatus => 'État du service';

  @override
  String get qdrantMetricRestEndpoint => 'Endpoint REST';

  @override
  String get qdrantMetricGrpcEndpoint => 'Endpoint gRPC';

  @override
  String get qdrantMetricQdrantVersion => 'Version Qdrant';

  @override
  String get qdrantMetricCurrentCollection => 'Collection actuelle';

  @override
  String get qdrantMetricCollectionStatus => 'État de collection';

  @override
  String get qdrantMetricOptimizerStatus => 'État de l’optimiseur';

  @override
  String get qdrantMetricLastHealthCheck => 'Dernier contrôle de santé';

  @override
  String get qdrantMetricDockerDaemon => 'Démon Docker';

  @override
  String get qdrantMetricContainerCpu => 'CPU du conteneur';

  @override
  String get qdrantMetricContainerMemory => 'Mémoire du conteneur';

  @override
  String get qdrantMetricNetworkIo => 'E/S réseau';

  @override
  String get qdrantMetricBlockIo => 'E/S bloc';

  @override
  String get qdrantMetricRestartCount => 'Redémarrages';

  @override
  String get qdrantMetricLatestLogSummary => 'Résumé des derniers logs';

  @override
  String get qdrantMetricCollectionsTotal => 'Collections totales';

  @override
  String get qdrantMetricPointsTotal => 'Points totaux';

  @override
  String get qdrantMetricVectorsTotal => 'Vecteurs totaux';

  @override
  String get qdrantMetricIndexedVectorsTotal => 'Vecteurs indexés totaux';

  @override
  String get qdrantMetricSegmentsTotal => 'Segments';

  @override
  String get qdrantMetricPayloadSchemaFields => 'Champs du schema Payload';

  @override
  String get qdrantMetricPayloadSchemaNames => 'Noms du schema Payload';

  @override
  String get qdrantMetricVectorSize => 'Dimension de vecteur';

  @override
  String get qdrantMetricDistance => 'Distance';

  @override
  String get qdrantMetricSingleNodeMode => 'Mode nœud unique';

  @override
  String get qdrantMetricPayloadIndexStatus => 'État de l’index Payload';

  @override
  String get qdrantMetricClusterStatus => 'État du cluster';

  @override
  String get qdrantMetricHnswM => 'HNSW M';

  @override
  String get qdrantMetricHnswEfConstruct => 'HNSW ef_construct';

  @override
  String get qdrantMetricHnswFullScanThreshold => 'Seuil HNSW full scan';

  @override
  String get qdrantMetricHnswMaxIndexingThreads =>
      'Threads d’indexation HNSW max';

  @override
  String get qdrantMetricOnDiskPayload => 'Payload sur disque';

  @override
  String get qdrantMetricShardNumber => 'Nombre de shards';

  @override
  String get qdrantMetricReplicationFactor => 'Facteur de réplication';

  @override
  String get qdrantMetricWriteConsistencyFactor =>
      'Facteur de cohérence écriture';

  @override
  String get qdrantMetricReadFanOutFactor => 'Facteur de fan-out lecture';

  @override
  String get qdrantMetricOptimizerDeletedThreshold =>
      'Seuil de suppression optimiseur';

  @override
  String get qdrantMetricOptimizerVacuumMinVectorNumber =>
      'Minimum de vecteurs pour vacuum';

  @override
  String get qdrantMetricOptimizerDefaultSegmentNumber =>
      'Nombre de segments par défaut';

  @override
  String get qdrantMetricOptimizerMaxSegmentSize => 'Taille max de segment';

  @override
  String get qdrantMetricOptimizerIndexingThreshold => 'Seuil d’indexation';

  @override
  String get qdrantMetricOptimizerFlushIntervalSeconds =>
      'Intervalle de flush (s)';

  @override
  String get qdrantMetricWalCapacityMb => 'Capacité WAL MB';

  @override
  String get qdrantMetricWalSegmentsAhead => 'Segments WAL en avance';

  @override
  String get qdrantMetricQuantization => 'Quantification';

  @override
  String get qdrantMetricStrictMode => 'Mode strict';

  @override
  String get qdrantMetricTelemetryStatus => 'État télémétrie';

  @override
  String get qdrantMetricAppVersion => 'Version de l’app';

  @override
  String get qdrantMetricAppName => 'Nom de l’app';

  @override
  String get qdrantMetricTelemetryCollections => 'Télémétrie collections';

  @override
  String get qdrantMetricTelemetryRequests => 'Télémétrie requêtes';

  @override
  String get qdrantMetricSourceCount => 'Sources';

  @override
  String get qdrantMetricChunkCount => 'Chunks';

  @override
  String get qdrantMetricPendingEmbeddingJobs =>
      'Tâches d’embedding en attente';

  @override
  String get qdrantMetricFailedEmbeddingJobs => 'Tâches d’embedding échouées';

  @override
  String get qdrantMetricEmbeddingModel => 'Modèle d’embedding actuel';

  @override
  String get qdrantMetricEmbeddingDimensions => 'Dimensions actuelles';

  @override
  String get qdrantMetricRetrievalTopN => 'Rappel topN';

  @override
  String get qdrantMetricRetrievalTopK => 'TopK final';

  @override
  String get qdrantMetricMinSimilarity => 'Similarité minimale';

  @override
  String get qdrantMetricPromptChunkBudget => 'Budget chunks du prompt';

  @override
  String get qdrantMetricPromptTokenBudget => 'Budget tokens du prompt';

  @override
  String get qdrantValueYes => 'Oui';

  @override
  String get qdrantValueNo => 'Non';

  @override
  String get qdrantValueHealthy => 'Sain';

  @override
  String get qdrantValueUnknown => 'Inconnu';

  @override
  String get qdrantValueLoading => 'Chargement';

  @override
  String get qdrantValueAvailable => 'Disponible';

  @override
  String get qdrantValueUnavailable => 'Indisponible';

  @override
  String get qdrantValuePluginServiceScan =>
      'Analysé par le service de plugins';

  @override
  String get qdrantValuePluginRuntimeMetric =>
      'Fourni par le runtime de plugin';

  @override
  String get qdrantValuePluginDetailsLogs =>
      'Disponible dans les détails du plugin';

  @override
  String get qdrantValueLocalSingleNodeOrUnavailable =>
      'Nœud unique local / indisponible';

  @override
  String get qdrantValueClusterInfoAvailable =>
      'Informations de cluster reçues';

  @override
  String get qdrantValuePayloadSchemaConfigured => 'Schema Payload configuré';

  @override
  String get qdrantValuePayloadSchemaMissing => 'Aucun schema Payload trouvé';
}
