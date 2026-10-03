// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get codeBlockDownload => 'Télécharger';

  @override
  String get codeBlockDownloaded => 'Téléchargé';

  @override
  String get codeBlockCode => 'Code';

  @override
  String get codeBlockView => 'Vue';

  @override
  String codeBlockLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lignes',
      one: '$count ligne',
    );
    return '$_temp0';
  }

  @override
  String get codeBlockCopiedMessage => 'Code copié.';

  @override
  String get codeBlockCopyFailed => 'Impossible de copier le code.';

  @override
  String codeBlockSavedMessage(String fileName) {
    return 'Code enregistré sous $fileName';
  }

  @override
  String get codeBlockSaveFailed => 'Impossible d’enregistrer le code.';

  @override
  String get maintenanceProcessId => 'ID du processus';

  @override
  String get maintenanceEgressAddress => 'Adresse publique';

  @override
  String get maintenanceEgressCopyAddress => 'Copier l’adresse publique';

  @override
  String get maintenanceEgressSource => 'Source des données';

  @override
  String get maintenanceEgressExtraField => 'Champ supplémentaire';

  @override
  String get maintenanceEgressTitle => 'Sortie Internet';

  @override
  String get maintenanceEgressRefresh => 'Actualiser la sortie';

  @override
  String get maintenanceEgressLoading =>
      'Recherche de la sortie de la machine cible';

  @override
  String get maintenanceEgressMissingTool =>
      'La machine cible nécessite curl ou wget';

  @override
  String get maintenanceEgressFailed =>
      'Échec de la recherche. Vérifiez la connexion Internet de la machine cible, puis actualisez.';

  @override
  String get maintenanceEgressStale =>
      'Échec de l’actualisation ; dernier résultat valide affiché';

  @override
  String get maintenanceEgressPending => 'En attente de la recherche';

  @override
  String get maintenanceEgressLocation => 'Localisation';

  @override
  String get maintenanceEgressNetwork => 'Réseau d’appartenance';

  @override
  String get maintenanceEgressTimezoneInfo => 'Fuseau horaire';

  @override
  String get maintenanceEgressCountryInfo => 'Informations sur le pays';

  @override
  String get maintenanceEgressExtra => 'Informations complémentaires';

  @override
  String get maintenanceEgressContinent => 'Continent';

  @override
  String get maintenanceEgressContinentCode => 'Code du continent';

  @override
  String get maintenanceEgressCountry => 'Pays ou région';

  @override
  String get maintenanceEgressCountryCode => 'Code du pays';

  @override
  String get maintenanceEgressCountryIso3 => 'Code pays à trois lettres';

  @override
  String get maintenanceEgressRegion => 'Région';

  @override
  String get maintenanceEgressRegionCode => 'Code de région';

  @override
  String get maintenanceEgressCity => 'Ville';

  @override
  String get maintenanceEgressLatitude => 'Latitude';

  @override
  String get maintenanceEgressLongitude => 'Longitude';

  @override
  String get maintenanceEgressPostal => 'Code postal';

  @override
  String get maintenanceEgressAsn => 'Numéro de système autonome';

  @override
  String get maintenanceEgressOrg => 'Organisation';

  @override
  String get maintenanceEgressIsp => 'Fournisseur d’accès Internet';

  @override
  String get maintenanceEgressDomain => 'Domaine du réseau';

  @override
  String get maintenanceEgressPrefix => 'Préfixe réseau';

  @override
  String get maintenanceEgressDatacenter => 'Centre de données';

  @override
  String get maintenanceEgressHosting => 'Réseau d’hébergement';

  @override
  String get maintenanceEgressProxy => 'Réseau proxy';

  @override
  String get maintenanceEgressVpn => 'Réseau VPN';

  @override
  String get maintenanceEgressTor => 'Réseau Tor';

  @override
  String get maintenanceEgressTimezone => 'Fuseau horaire';

  @override
  String get maintenanceEgressTimezoneAbbr => 'Abréviation du fuseau';

  @override
  String get maintenanceEgressDst => 'Heure d’été';

  @override
  String get maintenanceEgressOffsetSeconds => 'Décalage UTC (secondes)';

  @override
  String get maintenanceEgressOffset => 'Décalage UTC';

  @override
  String get maintenanceEgressLocalTime => 'Heure locale à la requête';

  @override
  String get maintenanceEgressEu => 'Membre de l’UE';

  @override
  String get maintenanceEgressCallingCode => 'Indicatif téléphonique';

  @override
  String get maintenanceEgressCapital => 'Capitale';

  @override
  String get maintenanceEgressBorders => 'Codes des pays voisins';

  @override
  String get maintenanceEgressFlagUrl => 'URL de l’image du drapeau';

  @override
  String get maintenanceEgressFlag => 'Drapeau';

  @override
  String get maintenanceEgressFlagCode => 'Codes des caractères du drapeau';

  @override
  String get maintenanceEgressTld => 'Domaine national';

  @override
  String get maintenanceEgressCurrency => 'Code de devise';

  @override
  String get maintenanceEgressCurrencyName => 'Nom de la devise';

  @override
  String get maintenanceEgressCurrencySymbol => 'Symbole monétaire';

  @override
  String get maintenanceEgressLanguages => 'Langues';

  @override
  String get maintenanceEgressArea => 'Superficie (km²)';

  @override
  String get maintenanceEgressPopulation => 'Population';

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
      'Configure les transitions du contenu principal à droite, notamment Workspace, Paramètres, MCP, Mémoire, Hooks de cycle de vie, Tâches planifiées, Compétences, Flux de travail et Automatisations.';

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
  String get cronScriptTypeManaged => 'Géré par le système';

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
  String get cronParserFieldSecond => 'Seconde';

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
  String get cronsTimeoutTooltip => 'Delai';

  @override
  String get cronsMcpKeywordIndexLockedTooltip =>
      'Controle par Parametres -> MCP -> Mode de mise a jour de l index de mots-cles';

  @override
  String get cronsRunOnceNow => 'Executer maintenant';

  @override
  String get cronsHistory => 'Historique';

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
  String get cronsCronSchedule => 'Planification Cron';

  @override
  String get cronsCronScheduleHelper =>
      'Le champ secondes reste a 0. Granularite minimale: minute. Format: min heure jour mois semaine';

  @override
  String get cronsEditorCreateSubtitle =>
      'Configurer l identite, le planning, la politique d execution et les notifications.';

  @override
  String get cronsEditorEditSubtitle =>
      'Ajuster le contenu, le planning et les notifications.';

  @override
  String get cronsSectionBasics => 'Informations';

  @override
  String get cronsSectionTask => 'Tache';

  @override
  String get cronsSectionSchedule => 'Planning';

  @override
  String get cronsSectionPolicy => 'Politique';

  @override
  String get cronsSectionRuntime => 'Environnement';

  @override
  String get cronsScriptTypeCommandHint => 'Executer une commande';

  @override
  String get cronsScriptTypeScriptHint => 'Executer le script selectionne';

  @override
  String get cronsExpressionPreview => 'Expression';

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
  String get skillsCreateDialogTitle => 'Créer une compétence';

  @override
  String get skillsCreateNameLabel => 'Nom de la compétence';

  @override
  String get skillsCreateNameRequired => 'Saisissez le nom de la compétence.';

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
  String get skillsEditorCreateSubtitle =>
      'Définir le nom, l\'icône et le manifeste SKILL.md.';

  @override
  String get skillsEditorEditSubtitle =>
      'Ajuster l\'identité, l\'icône et le manifeste de la compétence.';

  @override
  String get skillsSectionBasics => 'Informations de base';

  @override
  String get skillsSectionIcon => 'Icône de compétence';

  @override
  String get skillsSectionManifest => 'Manifeste';

  @override
  String get skillsSourceSystem => 'Système';

  @override
  String get skillsSourceLocal => 'Local';

  @override
  String get skillsHasDefaultPrompt => 'Invite par défaut';

  @override
  String get skillsPromptConfigured => 'Configurée';

  @override
  String get skillsPromptMissing => 'Absente';

  @override
  String get skillsMetricSource => 'Source';

  @override
  String get skillsMetricPrompt => 'Invite';

  @override
  String get imageEditorTitle => 'Modifier l’image';

  @override
  String get imageEditorCropHint =>
      'Faites glisser le cadre pour recadrer, puis zoomez, pivotez ou retournez l’image. Couleurs, détails, effets et filigranes sont prévisualisés en direct et enregistrés avec l’image.';

  @override
  String get imageEditorCompositionTitle => 'Composition';

  @override
  String get imageEditorCompositionSubtitle =>
      'Proportion, rotation et retournement';

  @override
  String get imageEditorBasicAdjustTitle => 'Réglages de base';

  @override
  String get imageEditorFileTypeImages => 'Images';

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
  String get imageEditorSectionColor => 'Couleur';

  @override
  String get imageEditorSectionColorSubtitle =>
      'Température, teinte et courbe des tons';

  @override
  String get imageEditorSectionSplitToning => 'Tonalité fractionnée';

  @override
  String get imageEditorSectionSplitToningSubtitle =>
      'Ombres et hautes lumières';

  @override
  String get imageEditorSectionDetail => 'Détail';

  @override
  String get imageEditorSectionDetailSubtitle =>
      'Clarté, netteté, réduction du bruit et grain';

  @override
  String get imageEditorSectionEffects => 'Effets';

  @override
  String get imageEditorSectionEffectsSubtitle =>
      'Dispersion, distorsion et vignettage';

  @override
  String get imageEditorSectionWatermark => 'Filigrane texte';

  @override
  String get imageEditorSectionWatermarkSubtitle =>
      'Texte, position et couleur';

  @override
  String get imageEditorTemperatureLabel => 'Température';

  @override
  String get imageEditorTintLabel => 'Décalage de teinte';

  @override
  String get imageEditorGammaLabel => 'Courbe des tons';

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
  String get imageEditorWatermarkPositionTopLeft => 'Haut gauche';

  @override
  String get imageEditorWatermarkPositionTopCenter => 'Haut centre';

  @override
  String get imageEditorWatermarkPositionTopRight => 'Haut droit';

  @override
  String get imageEditorWatermarkPositionMiddleLeft => 'Milieu gauche';

  @override
  String get imageEditorWatermarkPositionCenter => 'Centre';

  @override
  String get imageEditorWatermarkPositionMiddleRight => 'Milieu droit';

  @override
  String get imageEditorWatermarkPositionBottomLeft => 'Bas gauche';

  @override
  String get imageEditorWatermarkPositionBottomCenter => 'Bas centre';

  @override
  String get imageEditorWatermarkPositionBottomRight => 'Bas droit';

  @override
  String get imageEditorAdvancedApplyHint =>
      'Tous les réglages sont prévisualisés en direct puis appliqués à l’image exportée lors de l’enregistrement.';

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
  String get instructionBodyRequired => 'Saisissez le corps de l\'instruction.';

  @override
  String get instructionCreateAction => 'Créer';

  @override
  String get instructionSaveFailed =>
      'Échec de l\'enregistrement. Vérifiez que les champs obligatoires ne sont pas vides.';

  @override
  String get instructionEditorCreateSubtitle =>
      'Définir le nom, les déclencheurs et le corps de l\'instruction.';

  @override
  String get instructionEditorEditSubtitle =>
      'Ajuster le corps, les déclencheurs et l\'état d\'injection.';

  @override
  String get instructionSectionBasics => 'Informations de base';

  @override
  String get instructionSectionRouting => 'Déclencheurs';

  @override
  String get instructionSectionContent => 'Corps de l\'instruction';

  @override
  String get instructionSectionKeywords => 'Mots-clés';

  @override
  String get listCardMetricKind => 'Type';

  @override
  String get listCardMetricStatus => 'État';

  @override
  String get listCardMetricSize => 'Taille';

  @override
  String get listCardMetricUpdated => 'Mise à jour';

  @override
  String get listCardMetricContent => 'Contenu';

  @override
  String instructionSummaryVersion(String version) {
    return 'v$version';
  }

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
  String get memoryEditorCreateSubtitle =>
      'Écrivez ce qui doit être retenu, puis ajoutez des étiquettes optionnelles.';

  @override
  String get memoryEditorEditSubtitle =>
      'Ajuster le titre, le corps et les étiquettes de cette mémoire.';

  @override
  String get memorySectionBasics => 'Informations de base';

  @override
  String get memorySectionContent => 'Corps de la mémoire';

  @override
  String get memorySectionTags => 'Étiquettes';

  @override
  String get memoryAutoLearnedTag => 'Auto-appris';

  @override
  String memoryAutoLearnedLockedHint(String tag) {
    return '« $tag » identifie une mémoire auto-apprise et ne peut pas être retiré.';
  }

  @override
  String memoryAutoLearnedRestrictedHint(String tag) {
    return '« $tag » est réservé aux mémoires auto-apprises et ne peut pas être ajouté manuellement.';
  }

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
      'Détermine si les sorties d’outils trop longues deviennent des résumés structurés stables. L’activation réduit le coût des conversations et des points de compression ; la désactivation conserve la sortie brute.';

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
  String get imageEditorFineRotationLabel => 'Rotation fine (degrés)';

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
      'Image copiée dans le presse-papiers.';

  @override
  String get imageEditorApplyButton => 'Appliquer';

  @override
  String get imageEditorUndoButton => 'Annuler';

  @override
  String get imageEditorResetAllButton => 'Tout réinitialiser';

  @override
  String get imageEditorCompareHold => 'Maintenir pour comparer';

  @override
  String get imageEditorCompareRelease => 'Relâcher pour revenir';

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
  String get creationOptionsImageTitle => 'Options de génération d’image';

  @override
  String get creationOptionsImageSubtitle =>
      'Format, qualité et contrôles de génération';

  @override
  String get creationOptionsVideoTitle => 'Options de génération vidéo';

  @override
  String get creationOptionsVideoSubtitle =>
      'Image, mouvement et contrôles de génération';

  @override
  String get creationOptionsAudioTitle => 'Options de génération audio';

  @override
  String get creationOptionsAudioSubtitle => 'Voix, encodage et lecture';

  @override
  String get creationOptionsSectionFrame => 'Image';

  @override
  String get creationOptionsSectionFrameHint =>
      'Format, résolution et style de sortie';

  @override
  String get creationOptionsSectionMotion => 'Mouvement';

  @override
  String get creationOptionsSectionMotionHint =>
      'Durée, cadence et mode de génération';

  @override
  String get creationOptionsSectionGenerate => 'Génération';

  @override
  String get creationOptionsSectionGenerateHint =>
      'Renfort d’invite, filigrane et graine';

  @override
  String get creationOptionsSectionSound => 'Voix';

  @override
  String get creationOptionsSectionSoundHint =>
      'Voix, vitesse, volume et hauteur';

  @override
  String get creationOptionsSectionEncode => 'Encodage';

  @override
  String get creationOptionsSectionEncodeHint =>
      'Format, fréquence d’échantillonnage et débit';

  @override
  String get creationOptionsSectionCount => 'Quantité';

  @override
  String get creationOptionsSectionCountHint => 'Nombre d’éléments à générer';

  @override
  String get creationOptionsDecrease => 'Diminuer';

  @override
  String get creationOptionsIncrease => 'Augmenter';

  @override
  String get creationOptionsAspectRatio => 'Format';

  @override
  String get creationOptionsDuration => 'Durée';

  @override
  String creationOptionsDurationSeconds(int count) {
    return '$count s';
  }

  @override
  String get creationOptionsQuality => 'Qualité';

  @override
  String get creationOptionsStyle => 'Style';

  @override
  String get creationOptionsOutputFormat => 'Format de sortie';

  @override
  String get creationOptionsBackground => 'Arrière-plan';

  @override
  String get creationOptionsResolution => 'Résolution';

  @override
  String get creationOptionsFrameRate => 'Cadence';

  @override
  String creationOptionsFrameRateFps(int rate) {
    return '$rate im/s';
  }

  @override
  String get creationOptionsFrames => 'Images';

  @override
  String creationOptionsFramesValue(int count) {
    return '$count images';
  }

  @override
  String get creationOptionsMode => 'Mode';

  @override
  String get creationOptionsModeKeyframes => 'Images clés';

  @override
  String get creationOptionsPromptEnhance => 'Renfort d’invite';

  @override
  String get creationOptionsWatermark => 'Filigrane';

  @override
  String get creationOptionsNegativePrompt => 'Invite négative';

  @override
  String get creationOptionsSeed => 'Graine aléatoire';

  @override
  String get creationOptionsVoice => 'Voix';

  @override
  String get creationOptionsVoiceUnspecified => 'Non spécifiée';

  @override
  String get creationOptionsCustomVoice => 'Identifiant personnalisé';

  @override
  String get creationOptionsCustomVoiceId => 'Identifiant de voix personnalisé';

  @override
  String get creationOptionsAudioFormat => 'Format audio';

  @override
  String get creationOptionsSpeed => 'Vitesse';

  @override
  String creationOptionsMultiplier(String value) {
    return '×$value';
  }

  @override
  String get creationOptionsSampleRate => 'Fréquence d’échantillonnage';

  @override
  String creationOptionsSampleRateValue(int rate) {
    return '$rate Hz';
  }

  @override
  String get creationOptionsBitrate => 'Débit';

  @override
  String creationOptionsBitrateKbps(int rate) {
    return '$rate kbit/s';
  }

  @override
  String get creationOptionsVolume => 'Volume';

  @override
  String get creationOptionsPitch => 'Hauteur';

  @override
  String get creationOptionsAuto => 'Par défaut';

  @override
  String get creationOptionsOn => 'Oui';

  @override
  String get creationOptionsOff => 'Non';

  @override
  String get creationOptionsQualityAuto => 'Auto';

  @override
  String get creationOptionsQualityStandard => 'Standard';

  @override
  String get creationOptionsQualityHd => 'HD';

  @override
  String get creationOptionsQualityHigh => 'Maximale';

  @override
  String get creationOptionsStyleNatural => 'Naturel';

  @override
  String get creationOptionsStyleVivid => 'Vif';

  @override
  String get creationOptionsBackgroundAuto => 'Auto';

  @override
  String get creationOptionsBackgroundTransparent => 'Transparent';

  @override
  String get creationOptionsBackgroundOpaque => 'Opaque';

  @override
  String get creationOptionsPromptEnhanceOn => 'Invite renforcée';

  @override
  String get creationOptionsPromptEnhanceOff => 'Invite non renforcée';

  @override
  String get creationOptionsWatermarkOn => 'Avec filigrane';

  @override
  String get creationOptionsWatermarkOff => 'Sans filigrane';

  @override
  String get creationOptionsNegativeOn => 'Avec invite négative';

  @override
  String creationOptionsSeedValue(String value) {
    return 'Graine $value';
  }

  @override
  String creationOptionsCountValue(int count) {
    return '×$count';
  }

  @override
  String get creationOptionsImageMode => 'Génération d’image';

  @override
  String get creationOptionsVideoMode => 'Génération vidéo';

  @override
  String get creationOptionsAudioMode => 'Génération audio';

  @override
  String get creationOptionsDeepResearchMode => 'Recherche approfondie';

  @override
  String creationOptionsModeChip(String label) {
    return 'Mode · $label';
  }

  @override
  String get creationOptionsComposerImage => 'Image';

  @override
  String get creationOptionsComposerVideo => 'Vidéo';

  @override
  String get creationOptionsComposerAudio => 'Audio';

  @override
  String get creationOptionsComposerResearch => 'Recherche';

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
  String get tokenPopupContextHooks => 'Hooks de cycle de vie';

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
  String get mdlEdOpenRouterMetadataOverrides =>
      'Surcharges des métadonnées OpenRouter';

  @override
  String get mdlEdCanonicalSlug => 'Slug canonique du modèle';

  @override
  String get mdlEdHuggingFaceId => 'Identifiant du modèle Hugging Face';

  @override
  String get mdlEdKnowledgeCutoff => 'Date limite des connaissances';

  @override
  String get mdlEdExpirationDate => 'Date d’expiration';

  @override
  String get mdlEdSupportedParametersCsv => 'Paramètres pris en charge';

  @override
  String get mdlEdSupportedParametersCsvHint =>
      'Exemple : input, model, input_type, truncate';

  @override
  String get mdlEdDefaultParametersJson => 'Paramètres par défaut';

  @override
  String get mdlEdDefaultParametersJsonHint =>
      'Exemple : encoding_format: float';

  @override
  String get mdlEdOpenRouterRawMetadata => 'Métadonnées brutes OpenRouter';

  @override
  String get mdlEdOpenRouterRawMetadataFields =>
      'Identifiants du modèle, architecture, paramètres pris en charge, valeurs par défaut, voix, dates de fin des connaissances et d’expiration, et liens associés.';

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
  String get settingsCrons => 'Tâches planifiées';

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
      'Les résultats d’outils dépassant ce seuil deviennent des résumés structurés dès leur première insertion et gardent la même représentation afin de stabiliser le préfixe du cache. Valeur par défaut : 1024.';

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
  String get webReversePmHookStopped => 'Arrêté';

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
  String get exportKindHook => 'Événement de hook de cycle de vie';

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
  String get workflowsTitle => 'Flux de travail';

  @override
  String get workflowsSubtitle =>
      'Créez des automatisations réutilisables qui coordonnent plusieurs étapes et les exécutent dans l’ordre.';

  @override
  String get workflowsNew => 'Nouveau flux de travail';

  @override
  String get workflowsEmptyTitle => 'Aucun flux de travail';

  @override
  String get workflowsEmptyBody =>
      'Cliquez sur « Nouveau flux de travail » ci-dessus pour commencer.';

  @override
  String get hooksTitle => 'Hooks de cycle de vie';

  @override
  String get hooksSubtitle =>
      'Configurez les scripts de chaque étape du cycle de vie de l’agent IA. Les hooks de cycle de vie s’exécutent dans l’ordre lorsque l’événement correspondant se déclenche.';

  @override
  String get hooksNew => 'Nouveau hook de cycle de vie';

  @override
  String get hooksDeleteTitle => 'Supprimer le hook de cycle de vie';

  @override
  String hooksDeleteMessage(Object label) {
    return 'Supprimer « $label » ? Cette action est irréversible.';
  }

  @override
  String get hooksEmptyTitle => 'Aucun hook de cycle de vie';

  @override
  String get hooksEmptyBody =>
      'Cliquez sur « Nouveau hook de cycle de vie » ci-dessus pour commencer.';

  @override
  String get hooksTimeoutTooltip => 'Délai d’attente';

  @override
  String get hooksNoScriptConfigured => 'Aucun script configuré';

  @override
  String get hooksEditTitle => 'Modifier le hook de cycle de vie';

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
  String get hooksScriptContextInlineHelp =>
      'Le JSON de contexte est transmis de deux façons sûres (toutes deux compatibles avec jq) :\n① Fichier temporaire : SID=\$(jq -r .session_id \"\$OPENHAND_HOOK_CONTEXT_FILE\")\n② Octets bruts stdin : SID=\$(jq -r .session_id)\nChamps : session_id, session_file_path, environment, statistics, etc.';

  @override
  String get hooksTimeoutSeconds => 'Délai d’attente (secondes)';

  @override
  String get hooksEnabled => 'Activé';

  @override
  String get hooksEnabledBody =>
      'Désactivé, ce hook ne s\'exécute pas pour l\'événement choisi.';

  @override
  String get hooksEditorCreateSubtitle =>
      'Définir l\'événement, le script et le délai.';

  @override
  String get hooksEditorEditSubtitle =>
      'Ajuster l\'identité, le déclencheur et le script.';

  @override
  String get hooksSectionBasics => 'Informations de base';

  @override
  String get hooksSectionTrigger => 'Événement déclencheur';

  @override
  String get hooksSectionScript => 'Script';

  @override
  String get hooksSectionPolicy => 'Politique';

  @override
  String get hooksScriptSourceFileHint => 'Choisir un fichier de script local';

  @override
  String get hooksScriptSourceInlineHint => 'Écrire le script à exécuter';

  @override
  String get hooksValidationLabelRequired =>
      'Saisissez un nom de hook de cycle de vie.';

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

  @override
  String get mdlEdValueAuto => 'Automatique';

  @override
  String get mdlEdValueSupported => 'Pris en charge';

  @override
  String get mdlEdValueExperimental => 'Expérimental';

  @override
  String get mdlEdValueDisabled => 'Désactivé';

  @override
  String get mdlEdValueCustom => 'Personnalisé';

  @override
  String get mdlEdValueOpenaiCompat => 'Compatible OpenAI';

  @override
  String get mdlEdValueJevNative => 'Jev natif';

  @override
  String get mdlEdValueAnthropicNative => 'Anthropic natif';

  @override
  String get mdlEdValueGeminiNative => 'Gemini natif';

  @override
  String get mdlEdDecisionSummary =>
      'Protocole Jev : texte en entrée, résultats structurés de jugement, choix ou notation.';

  @override
  String get mdlEdDecisionProtocolHint =>
      'Pour les décisions structurées, sélectionnez Jev. Les fournisseurs mixtes peuvent utiliser une configuration Jev distincte.';

  @override
  String get mdlEdCatalogMissing =>
      'Aucune fiche correspondante. Suivez la documentation du fournisseur. Changer l’ID conserve les paramètres saisis.';

  @override
  String get mdlEdCatalogReference =>
      'Les valeurs du catalogue sont indicatives ; adaptez-les aux capacités du fournisseur.';

  @override
  String get mdlEdDecisionTitleUnavailable =>
      'Ce modèle renvoie des décisions structurées et ne peut pas générer de titres.';

  @override
  String get mdlEdJudgment => 'Jugement';

  @override
  String get mdlEdChoice => 'Choix';

  @override
  String get mdlEdScore => 'Note';

  @override
  String get mdlEdDecisionExtrasHint =>
      'Configurez les en-têtes et paramètres de requête dans decisions ; le corps contient uniquement model, state et questions.';

  @override
  String get mdlEdOperationExtrasHint =>
      'Paramètres du fournisseur pour les réponses, l’audio en temps réel et la vidéo.';

  @override
  String get maintenanceCenter => 'Exploitation du serveur';

  @override
  String get maintenanceEntry => 'Exploitation du serveur';

  @override
  String get maintenanceOverview => 'Vue d’ensemble';

  @override
  String get maintenanceProcesses => 'Processus';

  @override
  String get maintenanceServices => 'Services';

  @override
  String get maintenanceNetworkDiagnostics => 'Réseau et diagnostic';

  @override
  String get maintenanceSystemKernel => 'Système et noyau';

  @override
  String get maintenanceProcessorModel => 'Modèle du processeur';

  @override
  String get maintenanceLoadIntervals => 'Charge · 1 / 5 / 15 min';

  @override
  String get maintenancePressure => 'Pression · CPU / mémoire / E/S';

  @override
  String get maintenanceFilesystemCapacity =>
      'Capacité des systèmes de fichiers · KiB';

  @override
  String get maintenanceInodes => 'Inodes';

  @override
  String get maintenanceSwapSpace => 'Espace d’échange';

  @override
  String get maintenanceInterfaces => 'Liaisons et matériel réseau';

  @override
  String get maintenanceSensors => 'Capteurs de température';

  @override
  String get maintenanceMemoryDetails => 'Détails mémoire';

  @override
  String get maintenanceMemoryBasis => 'Méthode de mesure mémoire';

  @override
  String get maintenanceMemoryCounters => 'Compteurs mémoire et pagination';

  @override
  String get maintenanceVmCounters => 'Compteurs de mémoire virtuelle';

  @override
  String get maintenanceStartup => 'État au démarrage';

  @override
  String get maintenanceTimers => 'Minuteurs système';

  @override
  String get maintenanceSockets => 'Connexions et ports d’écoute';

  @override
  String get maintenanceRoutes => 'Adresses et routes';

  @override
  String get maintenanceDns => 'Configuration DNS';

  @override
  String get maintenanceLogs => 'Journaux récents';

  @override
  String get maintenanceUsers => 'Utilisateurs connectés';

  @override
  String get maintenanceCron => 'Tâches planifiées de l’utilisateur';

  @override
  String get maintenanceFirewall => 'Règles du pare-feu';

  @override
  String get maintenanceContainers => 'État des conteneurs';

  @override
  String get maintenanceStatusDetails => 'Détails de l’état';

  @override
  String get maintenanceCommand => 'Commande de lancement';

  @override
  String get maintenancePaths => 'Exécutable et répertoire de travail';

  @override
  String get maintenanceProcessIo => 'Compteurs E/S du processus';

  @override
  String get maintenanceLimits => 'Limites de ressources';

  @override
  String get maintenanceCgroup => 'Groupes de contrôle';

  @override
  String get maintenanceDescriptors => 'Descripteurs de fichiers ouverts';

  @override
  String get maintenanceCapabilities => 'Capacités de l’environnement';

  @override
  String get maintenanceBlocks => 'Périphériques blocs et RAID';

  @override
  String get maintenanceCgroupLimits =>
      'Limites des groupes · vues hôte et conteneur distinctes';

  @override
  String get maintenanceKernel => 'Paramètres du noyau';

  @override
  String get maintenanceNetworkCounters =>
      'Totaux réseau · octets, paquets, erreurs et pertes';

  @override
  String get maintenanceCollecting => 'Collecte en cours';

  @override
  String get maintenanceCollectionError => 'Erreur de collecte';

  @override
  String get maintenanceAutoRefresh => 'Actualisation auto';

  @override
  String get maintenanceManualRefresh => 'Actualisation manuelle';

  @override
  String get maintenanceDetecting => 'Détection du système cible';

  @override
  String get maintenanceAutoShell => 'Détecter le shell';

  @override
  String get maintenanceShell => 'Shell du terminal';

  @override
  String get maintenanceInterval => 'Intervalle d’actualisation';

  @override
  String get maintenanceFirstSample => 'En attente du premier relevé';

  @override
  String get maintenancePauseRefresh => 'Suspendre l’actualisation';

  @override
  String get maintenanceStartRefresh =>
      'Activer l’actualisation (section actuelle)';

  @override
  String get maintenanceRefreshSection => 'Actualiser cette section';

  @override
  String get maintenanceConnecting => 'Connexion au terminal';

  @override
  String get maintenanceUnavailableHost => 'État de la machine indisponible';

  @override
  String get maintenanceIdentifying =>
      'Identification du système et lecture de l’état';

  @override
  String get maintenanceCollectionFailed => 'La collecte n’a pas pu aboutir';

  @override
  String get maintenanceRetryHelp =>
      'Vérifiez la connexion du terminal et l’invite de commande, puis réessayez.';

  @override
  String get maintenanceRetry => 'Relancer la collecte';

  @override
  String get maintenanceMemory => 'Mémoire';

  @override
  String get maintenanceDisk => 'Disque';

  @override
  String get maintenanceNetwork => 'Réseau';

  @override
  String get maintenanceWaitingData => 'En attente des données cibles';

  @override
  String get maintenanceRawSample => 'Relevé actuel · sortie brute complète';

  @override
  String get maintenanceResourceUse => 'Utilisation des ressources';

  @override
  String get maintenanceUptime => 'Durée de fonctionnement';

  @override
  String get maintenanceLoad => 'Charge système';

  @override
  String get maintenanceProcessor => 'Processeur';

  @override
  String get maintenanceSampleStatus => 'État de l’échantillonnage';

  @override
  String get maintenanceStale => 'Données potentiellement périmées';

  @override
  String get maintenanceCollected => 'Collecte réussie';

  @override
  String get maintenanceRefreshMode => 'Mode d’actualisation';

  @override
  String get maintenanceTrendSamples => 'Échantillons de tendance';

  @override
  String get maintenanceTargetPlatform => 'Plateforme cible';

  @override
  String get maintenancePerCore => 'Charge par cœur';

  @override
  String maintenanceCoreLabel(String index) {
    return 'Cœur $index';
  }

  @override
  String get maintenanceBasicInfo => 'Informations générales';

  @override
  String get maintenanceRawSystem => 'Informations système brutes';

  @override
  String get maintenanceHost => 'Nom d’hôte';

  @override
  String get maintenanceOs => 'Système d’exploitation';

  @override
  String get maintenanceOsVersion => 'Version du système';

  @override
  String get maintenanceKernelVersion => 'Version du noyau';

  @override
  String get maintenanceLogicalCpus => 'Processeurs logiques';

  @override
  String get maintenanceStorage => 'Stockage';

  @override
  String get maintenanceFilesystem => 'Système de fichiers';

  @override
  String get maintenanceNoFilesystem => 'Aucun système de fichiers lisible';

  @override
  String get maintenanceThroughput => 'Débit réseau';

  @override
  String get maintenanceInterfaceDetails => 'Détails de l’interface réseau';

  @override
  String get maintenanceInterface => 'Interface';

  @override
  String get maintenanceReceiveRate => 'Reçu / s';

  @override
  String get maintenanceSendRate => 'Envoyé / s';

  @override
  String get maintenanceCpuTrend => 'Tendance CPU en direct';

  @override
  String get maintenanceAccumulating => 'Collecte des relevés…';

  @override
  String get maintenanceTrendHelp =>
      'En attente de mesures supplémentaires pour afficher la tendance';

  @override
  String get maintenanceOperations => 'Opérations';

  @override
  String get maintenanceViewProcesses => 'Voir les processus';

  @override
  String get maintenanceManageServices => 'Gérer les services';

  @override
  String get maintenanceNetworkAction => 'Diagnostic réseau';

  @override
  String get maintenanceAlerts => 'Alertes de ressources';

  @override
  String get maintenanceNoAlerts => 'Aucune alerte de seuil';

  @override
  String get maintenanceCpuUsage => 'Utilisation CPU';

  @override
  String get maintenanceMemoryUsage => 'Utilisation mémoire';

  @override
  String get maintenanceNoData => 'Aucune donnée';

  @override
  String get maintenanceSwapUsage => 'Utilisation du swap';

  @override
  String get maintenanceNoSwap => 'Swap non configuré';

  @override
  String get maintenanceMoreMetrics => 'Autres métriques système';

  @override
  String get maintenanceDiskIo => 'E/S disque';

  @override
  String get maintenanceDevice => 'Périphérique';

  @override
  String get maintenanceReadRate => 'Lecture / s';

  @override
  String get maintenanceWriteRate => 'Écriture / s';

  @override
  String get maintenanceReadIops => 'IOPS en lecture';

  @override
  String get maintenanceWriteIops => 'IOPS en écriture';

  @override
  String get maintenanceNoCounters =>
      'Aucun compteur disponible dans cet environnement.';

  @override
  String get maintenanceSearchProcess => 'Rechercher PID ou nom';

  @override
  String get maintenanceSortCpu => 'CPU décroissant';

  @override
  String get maintenanceSortMemory => 'Mémoire décroissante';

  @override
  String get maintenanceSortPid => 'PID croissant';

  @override
  String get maintenanceProcess => 'Processus';

  @override
  String get maintenanceStatus => 'État';

  @override
  String get maintenanceCpuPerCore => 'CPU / cœur';

  @override
  String get maintenanceResidentMemory => 'Mémoire résidente';

  @override
  String get maintenanceThreads => 'Threads';

  @override
  String get maintenanceUnavailable => 'Indisponible';

  @override
  String get maintenancePreviousBatch => 'Lot précédent';

  @override
  String get maintenanceNextBatch => 'Lot suivant';

  @override
  String get maintenanceRunning => 'En cours';

  @override
  String get maintenanceStopped => 'À l’arrêt';

  @override
  String get maintenanceUnknown => 'Inconnu';

  @override
  String get maintenanceFailed => 'En échec';

  @override
  String get maintenanceUnchecked => 'À vérifier';

  @override
  String get maintenanceDiscoveredServices => 'Services détectés';

  @override
  String get maintenanceVisibleServices => 'Services actuellement visibles';

  @override
  String get maintenanceFailedServices => 'Services en échec';

  @override
  String get maintenanceSearchService => 'Filtrer les services';

  @override
  String get maintenanceNoConnections =>
      'Aucune connexion TCP/UDP analysée. Consultez les données brutes.';

  @override
  String get maintenanceProtocol => 'Protocole';

  @override
  String get maintenanceLocalAddress => 'Adresse locale';

  @override
  String get maintenanceRemoteAddress => 'Adresse distante';

  @override
  String get maintenanceDnsServers => 'Serveurs DNS';

  @override
  String get maintenanceNoDns => 'Aucune adresse de serveur analysable';

  @override
  String get maintenanceDiagnosticItems => 'Vérifications diagnostiques';

  @override
  String get maintenanceParsedConnections => 'Connexions analysées';

  @override
  String get maintenanceNotProvided => 'Non fourni';

  @override
  String get maintenanceProcessRunning => 'En cours';

  @override
  String get maintenanceSleeping => 'En veille';

  @override
  String get maintenanceIdle => 'Inactif';

  @override
  String get maintenanceSuspended => 'Suspendu';

  @override
  String get maintenanceZombie => 'Zombie';

  @override
  String get maintenanceIoWait => 'Attente E/S';

  @override
  String get maintenancePartial =>
      'Partiellement indisponible · voir la raison';

  @override
  String get maintenanceViewCollected => 'Collecté · voir les détails';

  @override
  String get maintenanceNoAvailableData => 'Aucune donnée disponible';

  @override
  String get maintenanceViewDetails => 'Voir les détails';

  @override
  String get maintenanceConfirm => 'Confirmer l’exécution';

  @override
  String get maintenanceRefreshDetails => 'Actualiser les détails';

  @override
  String get maintenanceLoadingDetails => 'Chargement des détails…';

  @override
  String get maintenanceDetailsFailed => 'Échec du chargement. Réessayez.';

  @override
  String get maintenanceTerminate => 'Terminer le processus';

  @override
  String get maintenanceSuspend => 'Suspendre le processus';

  @override
  String get maintenanceResume => 'Reprendre le processus';

  @override
  String get maintenanceStartService => 'Démarrer le service';

  @override
  String get maintenanceStopService => 'Arrêter le service';

  @override
  String get maintenanceRestartService => 'Redémarrer le service';

  @override
  String get maintenanceEnableStartup => 'Activer au démarrage';

  @override
  String get maintenanceDisableStartup => 'Désactiver au démarrage';

  @override
  String get maintenanceAutomaticStartup => 'Démarrage automatique';

  @override
  String get maintenanceManualStartup => 'Démarrage manuel';

  @override
  String get maintenanceDisableService => 'Désactiver le service';

  @override
  String get maintenanceShellMismatch =>
      'Le shell ne correspond pas à la cible. Choisissez la détection auto ou le shell utilisé.';

  @override
  String maintenanceSeconds(String value) {
    return '$value s';
  }

  @override
  String maintenanceUpdated(String time) {
    return 'Mis à jour à $time';
  }

  @override
  String maintenanceCollectionErrorDetail(String error) {
    return 'Échec de collecte ; reprises suspendues. Données précédentes conservées. $error';
  }

  @override
  String maintenanceCpuAlert(String value) {
    return 'Utilisation CPU élevée : $value%';
  }

  @override
  String maintenanceMemoryAlert(String value) {
    return 'Utilisation mémoire élevée : $value%';
  }

  @override
  String maintenanceAutoInterval(String value) {
    return 'Auto · $value s';
  }

  @override
  String maintenanceAlertCount(String count) {
    return '$count éléments à surveiller';
  }

  @override
  String maintenanceCpuCount(String count) {
    return '$count processeurs logiques';
  }

  @override
  String maintenanceTotal(String value) {
    return 'Total $value';
  }

  @override
  String maintenanceMatched(String count, String total) {
    return '$count résultats · $total au total';
  }

  @override
  String maintenanceProcessTitle(String pid, String name) {
    return 'Processus $pid · $name';
  }

  @override
  String maintenanceServiceCount(String count) {
    return 'Services · $count';
  }

  @override
  String maintenanceServerNumber(String count) {
    return 'Serveur $count';
  }

  @override
  String maintenanceDuration(String days, String hours) {
    return '$days j $hours h';
  }

  @override
  String maintenanceConfirmAction(String target, String action) {
    return 'Cible : $target\nExécuter « $action » avec les droits du terminal ? Les tâches en cours peuvent être affectées.';
  }

  @override
  String maintenanceActionDone(String action) {
    return '$action exécuté. Actualisez pour voir l’état actuel.';
  }

  @override
  String get maintenanceEstablished => 'Établie';

  @override
  String get maintenanceListening => 'En écoute';

  @override
  String get maintenanceCloseWait => 'Fermeture en attente';

  @override
  String get maintenanceClosing => 'Fermeture';

  @override
  String get maintenanceTimeWait => 'Attente temporisée';

  @override
  String get maintenanceSynSent => 'Connexion demandée';

  @override
  String get maintenanceSynReceived => 'Demande de connexion reçue';

  @override
  String get maintenanceClosed => 'Fermée';

  @override
  String get maintenanceLastAck => 'Dernier acquittement attendu';

  @override
  String get maintenanceFinWait1 => 'Fermeture · attente d’acquittement';

  @override
  String get maintenanceFinWait2 => 'Fermeture · attente du pair';

  @override
  String get maintenanceUnconnected => 'Non connectée';

  @override
  String get maintenanceServiceStarting => 'Démarrage';

  @override
  String get maintenanceServiceStopping => 'Arrêt en cours';

  @override
  String get maintenanceProductName => 'Nom du produit';

  @override
  String get maintenanceProductVersion => 'Version du produit';

  @override
  String get maintenanceBuildVersion => 'Version de compilation';

  @override
  String get maintenanceRoutingTables => 'Tables de routage';

  @override
  String get maintenanceDnsConfiguration => 'Configuration DNS';

  @override
  String get maintenanceActiveInternet => 'Connexions Internet actives';

  @override
  String get maintenanceActiveMultipath =>
      'Connexions Internet multichemins actives';

  @override
  String get maintenanceActiveUnix => 'Sockets locaux (UNIX) actifs';

  @override
  String get maintenanceNameserver => 'Serveur de noms';

  @override
  String get maintenanceResolver => 'Résolveur';

  @override
  String get maintenanceIfIndex => 'Index d’interface';

  @override
  String get maintenanceFlags => 'Indicateurs';

  @override
  String get maintenanceReach => 'Accessibilité';

  @override
  String get maintenanceLocalizedFields => 'Champs traduits';

  @override
  String get maintenanceOriginalOutput => 'Sortie originale';

  @override
  String get maintenanceDestination => 'Destination';

  @override
  String get maintenanceGateway => 'Passerelle';

  @override
  String get maintenanceExpires => 'Expiration';

  @override
  String get maintenanceReceiveQueue => 'File de réception';

  @override
  String get maintenanceSendQueue => 'File d’envoi';

  @override
  String get maintenanceAddress => 'Adresse';

  @override
  String get maintenanceType => 'Type';

  @override
  String get maintenanceName => 'Nom';

  @override
  String get maintenanceDescription => 'Description';

  @override
  String get maintenanceParentPid => 'ID du processus parent';

  @override
  String get maintenanceUserId => 'ID utilisateur';

  @override
  String get maintenanceGroupId => 'ID du groupe';

  @override
  String get maintenancePriority => 'Priorité';

  @override
  String get maintenanceVirtualMemory => 'Mémoire virtuelle';

  @override
  String get maintenanceStartMode => 'Mode de démarrage';

  @override
  String get maintenanceExitCode => 'Code de sortie';

  @override
  String get maintenancePath => 'Chemin';

  @override
  String get maintenanceArchitecture => 'Architecture';

  @override
  String get maintenanceAvailableMemory => 'Mémoire disponible';

  @override
  String get maintenanceFreeMemory => 'Mémoire libre';

  @override
  String get maintenanceTotalMemory => 'Mémoire totale';

  @override
  String get maintenanceCachedMemory => 'Mémoire en cache';

  @override
  String get maintenanceBufferMemory => 'Mémoire tampon';

  @override
  String get maintenanceBytesRead => 'Octets lus';

  @override
  String get maintenanceBytesWritten => 'Octets écrits';

  @override
  String get maintenanceReceiveBytes => 'Octets reçus';

  @override
  String get maintenanceSendBytes => 'Octets envoyés';

  @override
  String get maintenanceMetricValue => 'Valeur';

  @override
  String get maintenanceMetricUnit => 'Unité';

  @override
  String get maintenanceMetricTotalReads => 'Lectures cumulées';

  @override
  String get maintenanceMetricTotalWrites => 'Écritures cumulées';

  @override
  String get maintenanceMetricBytesReadTotal => 'Octets lus cumulés';

  @override
  String get maintenanceMetricBytesWrittenTotal => 'Octets écrits cumulés';

  @override
  String get maintenanceMetricReadTimeTotal => 'Durée de lecture cumulée';

  @override
  String get maintenanceMetricWriteTimeTotal => 'Durée d’écriture cumulée';

  @override
  String get maintenanceMetricResource => 'Ressource';

  @override
  String get maintenanceMetricScope => 'Portée';

  @override
  String get maintenanceMetric10SecondAverage => 'Moyenne sur 10 s';

  @override
  String get maintenanceMetric60SecondAverage => 'Moyenne sur 60 s';

  @override
  String get maintenanceMetric300SecondAverage => 'Moyenne sur 300 s';

  @override
  String get maintenanceMetricTotalStallTime => 'Temps d’attente cumulé';

  @override
  String get maintenanceMetricPages => 'Pages';

  @override
  String get maintenanceMetricCount => 'Nombre';

  @override
  String get maintenanceMetricPageSize => 'Taille de page';

  @override
  String get maintenanceMetricFreeMemory => 'Mémoire libre';

  @override
  String get maintenanceMetricUsedInodes => 'Inodes utilisés';

  @override
  String get maintenanceMetricFreeInodes => 'Inodes libres';

  @override
  String get maintenanceMetricInodeUsage => 'Utilisation des inodes';

  @override
  String get maintenanceMetricMountPoint => 'Point de montage';

  @override
  String get maintenanceMetricCapacity => 'Capacité';

  @override
  String get maintenanceMetricParentDeviceBus => 'Périphérique parent / bus';

  @override
  String get maintenanceMetricMajorMinor => 'Majeur:mineur';

  @override
  String get maintenanceMetricRemovable => 'Amovible';

  @override
  String get maintenanceMetricReadOnly => 'Lecture seule';

  @override
  String get maintenanceMetricMembersAndSyncStatus =>
      'Membres et synchronisation';

  @override
  String get maintenanceMetricLinkGateway => 'Liaison / passerelle';

  @override
  String get maintenanceMetricKernelInterfaces => 'Interfaces du noyau';

  @override
  String get maintenanceMetricAvailableTools => 'Outils disponibles';

  @override
  String get maintenanceMetricMacosTools => 'Outils macOS';

  @override
  String get maintenanceMetricCumulativeDiskCounters =>
      'Compteurs disque cumulés';

  @override
  String
  get maintenanceMetricAvailableMemoryIncludesReclaimablePagesAccountingVaries =>
      'La mémoire disponible inclut les pages récupérables ; le calcul dépend du système.';

  @override
  String get maintenanceMetricSomeFieldsAreUnrecognizedOrUnavailableParsed =>
      'Certains champs sont inconnus ou indisponibles. Les indicateurs reconnus sont affichés.';

  @override
  String get maintenanceMetricSomeTasks => 'Certaines tâches';

  @override
  String get maintenanceMetricAllTasks => 'Toutes les tâches';

  @override
  String get maintenanceMetricSwapInPages => 'Pages entrantes';

  @override
  String get maintenanceMetricSwapOutPages => 'Pages sortantes';

  @override
  String get maintenanceMetricPageInVolume => 'Volume de pagination entrant';

  @override
  String get maintenanceMetricPageOutVolume => 'Volume de pagination sortant';

  @override
  String get maintenanceMetricTotalSwap => 'Swap total';

  @override
  String get maintenanceMetricFreeSwap => 'Swap libre';

  @override
  String get maintenanceMetricProcessLimit => 'Limite de processus';

  @override
  String get maintenanceMetricFileLimit => 'Limite de fichiers';

  @override
  String get maintenanceMetricThreadLimit => 'Limite de threads';

  @override
  String get maintenanceMetricConnected => 'Connecté';

  @override
  String get maintenanceMetricDisconnected => 'Déconnecté';

  @override
  String get maintenanceMetricPhysicalStore => 'Stockage physique';

  @override
  String get maintenanceMetricInternalPhysicalDisk => 'Disque physique interne';

  @override
  String get maintenanceMetricSynthesizedDisk => 'Disque synthétisé';

  @override
  String get maintenanceMetricDiskImage => 'Image disque';

  @override
  String get maintenanceMetricCommittedMemory => 'Mémoire engagée';

  @override
  String get maintenanceMetricTaskThreads => 'Threads des tâches';

  @override
  String get maintenanceMetricFileAllocated => 'Descripteurs alloués';

  @override
  String get maintenanceMetricFileUnused => 'Descripteurs libres';

  @override
  String get maintenanceMetricSwapTendency => 'Tendance au swap';

  @override
  String get maintenanceMetricListenLimit => 'Limite de file d’écoute';

  @override
  String get maintenanceMetricCpuQuota => 'Quota CPU';

  @override
  String get maintenanceMetricCpuPeriod => 'Période du quota CPU';

  @override
  String get maintenanceMetricMemoryLimit => 'Limite mémoire';

  @override
  String get maintenanceMetricMemoryCurrent => 'Mémoire actuelle';

  @override
  String get maintenanceMetricUnlimited => 'Illimité';

  @override
  String get maintenanceMetricActiveMemory => 'Mémoire active';

  @override
  String get maintenanceMetricInactiveMemory => 'Mémoire inactive';

  @override
  String get maintenanceMetricAnonymousMemory => 'Mémoire anonyme';

  @override
  String get maintenanceMetricSlabMemory => 'Cache d’objets du noyau';

  @override
  String get maintenanceMetricMappedMemory => 'Mémoire mappée';

  @override
  String get maintenanceMetricSharedMemory => 'Mémoire partagée';

  @override
  String get maintenanceMetricDirtyMemory => 'Mémoire modifiée';

  @override
  String get maintenanceMetricWritebackMemory => 'Mémoire en écriture';

  @override
  String get maintenanceMetricGuidScheme => 'Table de partitions GUID';

  @override
  String get maintenanceMetricApfsVolume => 'Volume APFS';

  @override
  String get maintenanceMetricApfsSnapshot => 'Instantané APFS';

  @override
  String get maintenanceMetricApfsContainer => 'Conteneur APFS';

  @override
  String maintenanceWorkers(String count) {
    return 'Jusqu’à $count processus';
  }

  @override
  String get maintenanceWorkersHelp =>
      'Nombre maximal de tâches de collecte simultanées. Appliqué à la prochaine actualisation.';

  @override
  String get maintenanceCounterPgalloc => 'Allocations de pages';

  @override
  String get maintenanceCounterPgfree => 'Pages libérées';

  @override
  String get maintenanceCounterPgactivate => 'Pages activées';

  @override
  String get maintenanceCounterPgdeactivate => 'Pages désactivées';

  @override
  String get maintenanceCounterPgfault => 'Défauts de page';

  @override
  String get maintenanceCounterPgmajfault => 'Défauts de page majeurs';

  @override
  String get maintenanceCounterPglazyfree => 'Demandes de libération différée';

  @override
  String get maintenanceCounterPglazyfreed => 'Pages libérées en différé';

  @override
  String get maintenanceCounterPgrefill => 'Recharges de pages';

  @override
  String get maintenanceCounterPgsteal => 'Pages récupérées';

  @override
  String get maintenanceCounterPgscan => 'Pages analysées';

  @override
  String get maintenanceCounterAllocstall => 'Blocages d’allocation';

  @override
  String get maintenanceCounterPgskip => 'Pages ignorées';

  @override
  String get maintenanceCounterPgrotated => 'Pages réordonnées';

  @override
  String get maintenanceCounterPginodesteal => 'Pages d’inodes récupérées';

  @override
  String get maintenanceCounterSlabsScanned => 'Analyses du cache slab';

  @override
  String get maintenanceCounterKswapdInodesteal =>
      'Récupération d’inodes en arrière-plan';

  @override
  String get maintenanceCounterKswapdLowWmarkHitQuickly =>
      'Atteintes rapides du seuil bas';

  @override
  String get maintenanceCounterKswapdHighWmarkHitQuickly =>
      'Atteintes rapides du seuil haut';

  @override
  String get maintenanceCounterPageoutrun =>
      'Cycles de récupération en arrière-plan';

  @override
  String get maintenanceCounterPgmigrateSuccess =>
      'Migrations de pages réussies';

  @override
  String get maintenanceCounterPgmigrateFail => 'Migrations de pages échouées';

  @override
  String get maintenanceCounterCompactStall => 'Blocages de compactage';

  @override
  String get maintenanceCounterCompactFail => 'Échecs de compactage';

  @override
  String get maintenanceCounterCompactSuccess => 'Compactages réussis';

  @override
  String get maintenanceCounterCompactMigrateScanned =>
      'Analyses de migration pour compactage';

  @override
  String get maintenanceCounterCompactFreeScanned =>
      'Analyses de pages libres pour compactage';

  @override
  String get maintenanceCounterCompactIsolated =>
      'Pages isolées pour compactage';

  @override
  String get maintenanceCounterUnevictable => 'Mémoire non récupérable';

  @override
  String get maintenanceCounterMlocked => 'Mémoire verrouillée';

  @override
  String get maintenanceCounterAnon => 'Pages anonymes';

  @override
  String get maintenanceCounterFile => 'Pages de fichiers';

  @override
  String get maintenanceCounterActive => 'Actif';

  @override
  String get maintenanceCounterInactive => 'Inactif';

  @override
  String get maintenanceCounterIsolated => 'Pages isolées';

  @override
  String get maintenanceCounterSlabReclaimable => 'Cache slab récupérable';

  @override
  String get maintenanceCounterSlabUnreclaimable =>
      'Cache slab non récupérable';

  @override
  String get maintenanceCounterKernelStack => 'Pile du noyau';

  @override
  String get maintenanceCounterPageTablePages => 'Tables de pages';

  @override
  String get maintenanceCounterBounce => 'Tampons de rebond';

  @override
  String get maintenanceCounterWritebackTemp => 'Réécriture temporaire';

  @override
  String get maintenanceCounterWriteback => 'Pages en réécriture';

  @override
  String get maintenanceCounterDirtied => 'Pages modifiées';

  @override
  String get maintenanceCounterWritten => 'Pages écrites';

  @override
  String get maintenanceCounterDirtyThreshold => 'Seuil de pages modifiées';

  @override
  String get maintenanceCounterDirtyBackgroundThreshold =>
      'Seuil de réécriture en arrière-plan';

  @override
  String get maintenanceCounterNumaHit => 'Allocations NUMA réussies';

  @override
  String get maintenanceCounterNumaMiss => 'Allocations NUMA manquées';

  @override
  String get maintenanceCounterNumaForeign => 'Allocations NUMA externes';

  @override
  String get maintenanceCounterNumaInterleave => 'Allocations NUMA entrelacées';

  @override
  String get maintenanceCounterNumaLocal => 'Allocations NUMA locales';

  @override
  String get maintenanceCounterNumaOther =>
      'Allocations sur d’autres nœuds NUMA';

  @override
  String get maintenanceCounterNormal => 'Zone normale';

  @override
  String get maintenanceCounterMovable => 'Zone déplaçable';

  @override
  String get maintenanceCounterHigh => 'Zone mémoire haute';

  @override
  String get maintenanceCounterKswapd => 'Récupération en arrière-plan';

  @override
  String get maintenanceCounterDirect => 'Récupération directe';

  @override
  String get maintenanceCounterThrottle => 'Limitation';

  @override
  String get maintenanceCounterSwapcached => 'Cache d’échange';

  @override
  String get maintenanceCounterCommitlimit => 'Limite d’engagement';

  @override
  String get maintenanceCounterVmalloctotal => 'Espace virtuel total du noyau';

  @override
  String get maintenanceCounterVmallocused => 'Espace virtuel utilisé du noyau';

  @override
  String get maintenanceCounterVmallocchunk =>
      'Plus grand bloc virtuel du noyau';

  @override
  String get maintenanceCounterAnonhugepages => 'Pages géantes anonymes';

  @override
  String get maintenanceCounterShmemhugepages =>
      'Pages géantes de mémoire partagée';

  @override
  String get maintenanceCounterShmempmdmapped =>
      'Mappages PMD de mémoire partagée';

  @override
  String get maintenanceCounterHugepagesTotal => 'Total des pages géantes';

  @override
  String get maintenanceCounterHugepagesFree => 'Pages géantes libres';

  @override
  String get maintenanceCounterHugepagesRsvd => 'Pages géantes réservées';

  @override
  String get maintenanceCounterHugepagesSurp => 'Pages géantes supplémentaires';

  @override
  String get maintenanceCounterHugepagesize => 'Taille des pages géantes';

  @override
  String get maintenanceCounterHugetlb => 'Mémoire des pages géantes';

  @override
  String get maintenanceCounterPercpu => 'Mémoire par processeur';

  @override
  String get maintenanceCounterHardwarecorrupted =>
      'Mémoire corrompue matériellement';

  @override
  String get maintenanceCounterKreclaimable => 'Mémoire récupérable du noyau';

  @override
  String get maintenanceCounterNfsUnstable => 'Pages NFS non stabilisées';

  @override
  String get maintenanceCounterWorkingsetRefault =>
      'Nouveaux défauts du jeu de travail';

  @override
  String get maintenanceCounterWorkingsetActivate =>
      'Activations du jeu de travail';

  @override
  String get maintenanceCounterWorkingsetRestore =>
      'Restaurations du jeu de travail';

  @override
  String get maintenanceCounterWorkingsetNodereclaim =>
      'Récupération de nœuds du jeu de travail';

  @override
  String get maintenanceCounterThpFaultAlloc => 'Allocations THP sur défaut';

  @override
  String get maintenanceCounterThpFaultFallback => 'Replis THP sur défaut';

  @override
  String get maintenanceCounterThpCollapseAlloc => 'Allocations THP par fusion';

  @override
  String get maintenanceCounterThpCollapseAllocFailed =>
      'Échecs d’allocation THP par fusion';

  @override
  String get maintenanceCounterThpSplitPage => 'Divisions de pages THP';

  @override
  String get maintenanceCounterThpSplitPageFailed => 'Échecs de division THP';

  @override
  String get maintenanceCounterThpSplitPmd => 'Divisions PMD THP';

  @override
  String get maintenanceCounterThpZeroPageAlloc =>
      'Allocations de pages zéro THP';

  @override
  String get maintenanceCounterThpZeroPageAllocFailed =>
      'Échecs d’allocation de pages zéro THP';

  @override
  String get maintenanceCounterThpDeferredSplitPage =>
      'Divisions THP différées';

  @override
  String get maintenanceCounterThpSwpout => 'Sorties de swap THP';

  @override
  String get maintenanceCounterThpSwpoutFallback =>
      'Replis de sortie de swap THP';

  @override
  String get maintenanceCounterUnevictablePgsCulled =>
      'Pages rendues non récupérables';

  @override
  String get maintenanceCounterUnevictablePgsScanned =>
      'Pages non récupérables analysées';

  @override
  String get maintenanceCounterUnevictablePgsRescued =>
      'Pages à nouveau récupérables';

  @override
  String get maintenanceCounterUnevictablePgsMlocked => 'Pages verrouillées';

  @override
  String get maintenanceCounterUnevictablePgsMunlocked =>
      'Pages déverrouillées';

  @override
  String get maintenanceCounterUnevictablePgsCleared =>
      'Marques non récupérables effacées';

  @override
  String get maintenanceCounterUnevictablePgsStranded =>
      'Pages non récupérables bloquées';

  @override
  String get maintenanceCounterOomKill => 'Arrêts pour manque de mémoire';

  @override
  String get maintenanceCounterNumaPteUpdates => 'Mises à jour PTE NUMA';

  @override
  String get maintenanceCounterNumaHugePteUpdates =>
      'Mises à jour PTE géantes NUMA';

  @override
  String get maintenanceCounterNumaHintFaults => 'Défauts indicatifs NUMA';

  @override
  String get maintenanceCounterNumaHintFaultsLocal =>
      'Défauts indicatifs NUMA locaux';

  @override
  String get maintenanceCounterNumaPagesMigrated => 'Pages NUMA migrées';

  @override
  String get maintenanceCounterCompactDaemonWake =>
      'Réveils du démon de compactage';

  @override
  String get maintenanceCounterCompactDaemonMigrateScanned =>
      'Analyses de migration du compactage en arrière-plan';

  @override
  String get maintenanceCounterCompactDaemonFreeScanned =>
      'Analyses de pages libres du compactage en arrière-plan';

  @override
  String get maintenanceCounterVmscanWrite =>
      'Écritures lors des analyses de récupération';

  @override
  String get maintenanceCounterVmscanImmediateReclaim =>
      'Récupération immédiate après analyse';

  @override
  String get maintenanceCounterFollPinAcquired => 'Fixations de pages acquises';

  @override
  String get maintenanceCounterFollPinReleased => 'Fixations de pages libérées';

  @override
  String get maintenanceCounterAnonTransparentHugepages =>
      'Pages géantes transparentes anonymes';

  @override
  String get maintenanceCounterShmemHugepages =>
      'Pages géantes de mémoire partagée';

  @override
  String get maintenanceCounterShmemPmdmapped =>
      'Mappages PMD de mémoire partagée';

  @override
  String get maintenanceCounterFileHugepages => 'Pages géantes de fichiers';

  @override
  String get maintenanceCounterFilePmdmapped => 'Mappages PMD de fichiers';

  @override
  String get maintenanceCounterFreeCma => 'Mémoire CMA libre';

  @override
  String get maintenanceCounterCmatotal => 'Mémoire CMA totale';

  @override
  String get maintenanceCounterPagereadspersec => 'Débit de lecture des pages';

  @override
  String get maintenanceCounterPagewritespersec => 'Débit d’écriture des pages';

  @override
  String get maintenanceCounterPagesinputpersec => 'Débit d’entrée des pages';

  @override
  String get maintenanceCounterPagesoutputpersec => 'Débit de sortie des pages';

  @override
  String get maintenanceCounterPagespersec => 'Débit de pagination';

  @override
  String get maintenanceCounterPoolpagedbytes => 'Mémoire du pool paginé';

  @override
  String get maintenanceCounterPoolnonpagedbytes =>
      'Mémoire du pool non paginé';

  @override
  String get maintenanceCounterCachebytes => 'Octets du cache';

  @override
  String get maintenanceCounterPercentcommittedbytesinuse =>
      'Utilisation de mémoire engagée';

  @override
  String get maintenanceCounterSystemcodetotalbytes =>
      'Mémoire totale du code système';

  @override
  String get maintenanceCounterSystemdrivertotalbytes =>
      'Mémoire totale des pilotes système';

  @override
  String maintenanceExtendedMetric(String name) {
    return 'Indicateur supplémentaire : $name';
  }

  @override
  String get maintenanceShowExactValue => 'Afficher la valeur exacte';

  @override
  String get maintenanceShowReadableValue => 'Afficher la valeur simplifiée';

  @override
  String get maintenanceDetailUser => 'Utilisateur';

  @override
  String get maintenanceDetailTerminal => 'Terminal';

  @override
  String get maintenanceDetailLoginTime => 'Heure de connexion';

  @override
  String get maintenanceDetailSource => 'Source';

  @override
  String get maintenanceDetailTarget => 'Cible';

  @override
  String get maintenanceDetailPermissions => 'Autorisations';

  @override
  String get maintenanceDetailSchedule => 'Planification';

  @override
  String get maintenanceDetailTime => 'Heure';

  @override
  String get maintenanceDetailMessage => 'Message';

  @override
  String get maintenanceDetailImage => 'Image';

  @override
  String get maintenanceDetailCreated => 'Création';

  @override
  String get maintenanceDetailPorts => 'Ports';

  @override
  String get maintenanceDetailRestartPolicy => 'Politique de redémarrage';

  @override
  String get maintenanceDetailNotifyAccess => 'Accès aux notifications';

  @override
  String get maintenanceDetailRestartDelay => 'Délai de redémarrage';

  @override
  String get maintenanceDetailStartTimeout => 'Délai de démarrage';

  @override
  String get maintenanceDetailStopTimeout => 'Délai d’arrêt';

  @override
  String get maintenanceDetailWatchdogTimeout => 'Délai du watchdog';

  @override
  String get maintenanceDetailUmask => 'Masque de permissions';

  @override
  String get maintenanceDetailTracer => 'Processus traceur';

  @override
  String get maintenanceDetailDescriptorLimit => 'Capacité des descripteurs';

  @override
  String get maintenanceDetailSoftLimit => 'Limite souple';

  @override
  String get maintenanceDetailHardLimit => 'Limite stricte';

  @override
  String get maintenanceDetailEnabled => 'Activé';

  @override
  String get maintenanceDetailDisabled => 'Désactivé';

  @override
  String get maintenanceDetailNone => 'Aucun';

  @override
  String get maintenanceDetailSearchDomain => 'Domaines de recherche';

  @override
  String get maintenanceDetailDomain => 'Domaine';

  @override
  String get maintenanceDetailOptions => 'Options';

  @override
  String get maintenanceCpuTime => 'Temps CPU';

  @override
  String get maintenanceLoadState => 'État de chargement';

  @override
  String get maintenanceSubState => 'Sous-état';

  @override
  String get maintenanceTaskCount => 'Tâches';

  @override
  String get maintenanceRestartCount => 'Redémarrages';

  @override
  String get maintenanceLoaded => 'Chargé';

  @override
  String get maintenanceExited => 'Terminé';

  @override
  String get maintenanceStatic => 'Statique';

  @override
  String get maintenanceMasked => 'Masqué';

  @override
  String get maintenanceTrendGesture =>
      'Pincer pour zoomer · Glisser pour déplacer · Double-clic pour réinitialiser';

  @override
  String get maintenanceMemoryShare => 'Répartition mémoire';

  @override
  String get maintenanceUsed => 'Utilisée';

  @override
  String get maintenanceAvailable => 'Disponible';

  @override
  String get maintenanceCpuRank => 'CPU · 6 processus échantillonnés en tête';

  @override
  String get maintenanceMemoryRank =>
      'Mémoire résidente · 6 processus échantillonnés en tête';

  @override
  String get maintenanceServiceShare => 'Répartition des états des services';

  @override
  String get maintenanceConnectionShare =>
      'Répartition des états des connexions';

  @override
  String get maintenanceConnectionGraph =>
      'Connexions entre points de terminaison';

  @override
  String get maintenanceGraphScope =>
      '6 paires échantillonnées au maximum ; les nombres indiquent les connexions. Les ports en écoute figurent ci-dessous.';

  @override
  String get maintenanceStartupSystemAgent => 'Agent système';

  @override
  String get maintenanceStartupUserAgent => 'Agent utilisateur';

  @override
  String get maintenanceStartupDaemon => 'Démon système';

  @override
  String get maintenanceStartupPreset => 'Préréglage';

  @override
  String get maintenanceStartupIndirect => 'Indirect';

  @override
  String get maintenanceStartupGenerated => 'Généré';

  @override
  String get maintenanceStartupTransient => 'Temporaire';

  @override
  String get maintenanceStartupAlias => 'Alias';

  @override
  String get maintenanceStartupLinked => 'Lié';

  @override
  String get maintenanceStartupEnabledRuntime => 'Activé jusqu’au redémarrage';

  @override
  String get maintenanceStartupMaskedRuntime => 'Masqué jusqu’au redémarrage';

  @override
  String get maintenanceStartupLinkedRuntime => 'Lié jusqu’au redémarrage';

  @override
  String get maintenanceListView => 'Liste';

  @override
  String get maintenanceTreeView => 'Arbre des relations';

  @override
  String get maintenanceNameTree => 'Groupes de noms';

  @override
  String get maintenanceTreeExpand => 'Développer';

  @override
  String get maintenanceTreeCollapse => 'Réduire';

  @override
  String get maintenanceTreeDependencies => 'Dépendances';

  @override
  String get maintenanceGpuTab => 'Gestion GPU';

  @override
  String get maintenanceGpuUtil => 'Utilisation GPU';

  @override
  String get maintenanceGpuMemoryUsed => 'VRAM utilisée';

  @override
  String get maintenanceGpuMemoryTotal => 'VRAM totale';

  @override
  String get maintenanceGpuTemperature => 'Température';

  @override
  String get maintenanceGpuPower => 'Puissance';

  @override
  String get maintenanceGpuPowerLimit => 'Limite de puissance';

  @override
  String get maintenanceGpuCoreClock => 'Fréquence du cœur';

  @override
  String get maintenanceGpuMemoryClock => 'Fréquence mémoire';

  @override
  String get maintenanceGpuFan => 'Vitesse relative du ventilateur';

  @override
  String get maintenanceGpuFanRpm => 'Vitesse du ventilateur';

  @override
  String get maintenanceGpuRenderer => 'Utilisation du moteur de rendu';

  @override
  String get maintenanceGpuTiler => 'Utilisation du moteur de tuilage';

  @override
  String get maintenanceGpuSharedUsed => 'Mémoire partagée utilisée';

  @override
  String get maintenanceGpuSharedAllocated => 'Mémoire partagée allouée';

  @override
  String get maintenanceGpuRecoveries => 'Récupérations';

  @override
  String get maintenanceGpuCores => 'Cœurs GPU';

  @override
  String get maintenanceGpuEmpty => 'Aucune donnée GPU disponible';

  @override
  String get maintenanceGpuTrend => 'Évolution de l’utilisation GPU';

  @override
  String get maintenanceGpuMemoryFree => 'VRAM libre';

  @override
  String get maintenanceGpuSource => 'Source';

  @override
  String get maintenanceGpuVendor => 'Fabricant';

  @override
  String get maintenanceGpuDriver => 'Version du pilote';

  @override
  String get maintenanceGpuBus => 'Bus';

  @override
  String get maintenanceGpuProcesses => 'Processus de calcul GPU';

  @override
  String get maintenanceGpuDisplays => 'Écrans connectés';

  @override
  String get maintenanceGpuPixels => 'Pixels physiques';

  @override
  String get maintenanceGpuResolution => 'Mode d’affichage';

  @override
  String get maintenanceLogsTab => 'Journaux';

  @override
  String get maintenanceLogSystem => 'Journaux système';

  @override
  String get maintenanceLogKernel => 'Journaux du noyau';

  @override
  String get maintenanceLogSecurity => 'Journaux de sécurité';

  @override
  String get maintenanceLogApplication => 'Journaux applicatifs';

  @override
  String get maintenanceLogSearch => 'Rechercher dans les journaux';

  @override
  String get maintenanceLogFollow => 'Suivre les nouveaux événements';

  @override
  String get maintenanceLogClear => 'Effacer l’écran';

  @override
  String get maintenanceLogAll => 'Tous les niveaux';

  @override
  String get maintenanceLogError => 'Erreur';

  @override
  String get maintenanceLogWarning => 'Avertissement';

  @override
  String get maintenanceLogInfo => 'Information';

  @override
  String get maintenanceLogRotation => 'Rotation et configuration';

  @override
  String get maintenanceLogUnavailable => 'Source de journaux indisponible';

  @override
  String get maintenanceLogEmpty => 'Aucun événement';

  @override
  String get maintenanceLogStorage => 'Taille du dossier des journaux';

  @override
  String get maintenanceHealthTab => 'Accès et santé';

  @override
  String get maintenanceHealthSessions => 'Sessions actives';

  @override
  String get maintenanceHealthLogins => 'Connexions récentes';

  @override
  String get maintenanceHealthAccounts => 'Comptes locaux';

  @override
  String get maintenanceHealthPassword => 'État et règles des mots de passe';

  @override
  String get maintenanceHealthSsh => 'Configuration SSH';

  @override
  String get maintenanceHealthTemperature => 'Température et état thermique';

  @override
  String get maintenanceHealthPower => 'Alimentation et batterie';

  @override
  String get maintenanceHealthClock => 'Synchronisation horaire';

  @override
  String get maintenanceHealthUnavailable => 'Actuellement indisponible';

  @override
  String get maintenanceHealthUnsupported => 'Non fourni par cette plateforme';

  @override
  String get maintenanceHealthSensor => 'Capteur';

  @override
  String get maintenanceHealthUser => 'Compte';

  @override
  String get maintenanceHealthHome => 'Dossier personnel';

  @override
  String get maintenanceHealthDate => 'Date, heure et fuseau horaire';

  @override
  String get maintenanceHealthNtp => 'Services et sources NTP / Chrony';

  @override
  String get maintenanceTerminalBusy =>
      'Le terminal effectue une opération de fichier ou de maintenance. Actualisez à nouveau dans un instant.';

  @override
  String get maintenanceCommandTimedOut =>
      'Le terminal ne répond pas. Vérifiez qu’il est prêt et affiche une invite de commande, puis réessayez.';

  @override
  String get maintenanceHealthParsedInsufficientPermissionsForThisAccount =>
      'Droits insuffisants pour ce compte';

  @override
  String get maintenanceHealthParsedCollectionToolIsMissingOrUnavailable =>
      'Outil de collecte absent ou indisponible';

  @override
  String
  get maintenanceHealthParsedSSHConfigurationCheckFailedHostKeysUnavailable =>
      'Échec de vérification SSH : clés hôte indisponibles';

  @override
  String
  get maintenanceHealthParsedUnrecognizedDataFormatInspectCollectionDetails =>
      'Format non reconnu ; consulter les détails';

  @override
  String get maintenanceHealthParsedNotCollectedYet => 'Pas encore collecté';

  @override
  String get maintenanceHealthParsedCollectionDetailsAndDiagnostics =>
      'Détails de collecte et diagnostic';

  @override
  String get maintenanceHealthParsedAccount => 'Compte';

  @override
  String get maintenanceHealthParsedHomeDirectory => 'Dossier personnel';

  @override
  String get maintenanceHealthParsedSensor => 'Capteur';

  @override
  String get maintenanceHealthParsedLoginTime => 'Heure de connexion';

  @override
  String get maintenanceHealthParsedIdleTime => 'Temps inactif';

  @override
  String get maintenanceHealthParsedSource => 'Source';

  @override
  String get maintenanceHealthParsedLocalTime => 'Heure locale';

  @override
  String get maintenanceHealthParsedTimeZone => 'Fuseau horaire';

  @override
  String get maintenanceHealthParsedArchitecture => 'Architecture';

  @override
  String get maintenanceHealthParsedSystemName => 'Nom du système';

  @override
  String get maintenanceHealthParsedSystemVersion => 'Version du système';

  @override
  String get maintenanceHealthParsedBuildVersion => 'Version de compilation';

  @override
  String get maintenanceHealthParsedPowerSource => 'Source électrique';

  @override
  String get maintenanceHealthParsedBatteryCharge => 'Charge de batterie';

  @override
  String get maintenanceHealthParsedThermalWarning => 'Alerte thermique';

  @override
  String get maintenanceHealthParsedPerformanceWarning =>
      'Alerte de performance';

  @override
  String get maintenanceHealthParsedCPUPowerStatus => 'État énergétique du CPU';

  @override
  String get maintenanceHealthParsedPolicyIdentifier =>
      'Identifiant de stratégie';

  @override
  String get maintenanceHealthParsedPolicyExpression =>
      'Expression de stratégie';

  @override
  String get maintenanceHealthParsedPasswordStatus => 'État du mot de passe';

  @override
  String get maintenanceHealthParsedLastChange => 'Dernière modification';

  @override
  String get maintenanceHealthParsedMinimumAgeDays => 'Âge minimal (jours)';

  @override
  String get maintenanceHealthParsedMaximumAgeDays => 'Âge maximal (jours)';

  @override
  String get maintenanceHealthParsedExpiryWarningDays =>
      'Avertissement (jours)';

  @override
  String get maintenanceHealthParsedInactivityDays => 'Inactivité (jours)';

  @override
  String get maintenanceHealthParsedListeningPort => 'Port d’écoute';

  @override
  String get maintenanceHealthParsedListeningAddress => 'Adresse d’écoute';

  @override
  String get maintenanceHealthParsedRootLoginPolicy => 'Connexion root';

  @override
  String get maintenanceHealthParsedPasswordAuthentication =>
      'Authentification par mot de passe';

  @override
  String get maintenanceHealthParsedPublicKeyAuthentication =>
      'Authentification par clé';

  @override
  String get maintenanceHealthParsedInteractiveAuthentication =>
      'Authentification interactive';

  @override
  String get maintenanceHealthParsedAllowEmptyPasswords =>
      'Autoriser les mots de passe vides';

  @override
  String get maintenanceHealthParsedMaximumAuthenticationAttempts =>
      'Tentatives maximales';

  @override
  String get maintenanceHealthParsedMaximumSessions => 'Sessions maximales';

  @override
  String get maintenanceHealthParsedLoginGraceTimeS => 'Délai de connexion (s)';

  @override
  String get maintenanceHealthParsedKeepaliveIntervalS =>
      'Intervalle de maintien (s)';

  @override
  String get maintenanceHealthParsedMaximumMissedKeepalives =>
      'Échecs de maintien maximaux';

  @override
  String get maintenanceHealthParsedAuthenticationMethods =>
      'Méthodes d’authentification';

  @override
  String get maintenanceHealthParsedClockSynchronized => 'Horloge synchronisée';

  @override
  String get maintenanceHealthParsedNetworkTimeEnabled =>
      'Heure réseau activée';

  @override
  String get maintenanceHealthParsedRTCUsesLocalTime => 'RTC en heure locale';

  @override
  String get maintenanceHealthParsedNetworkTime => 'Heure réseau';

  @override
  String get maintenanceHealthParsedTimeServer => 'Serveur de temps';

  @override
  String get maintenanceHealthParsedPollingInterval => 'Intervalle de sondage';

  @override
  String get maintenanceHealthParsedReachRegisterOctal =>
      'Registre de portée (octal)';

  @override
  String get maintenanceHealthParsedStratum => 'Strate';

  @override
  String get maintenanceHealthParsedClockOffset => 'Décalage temporel';

  @override
  String get maintenanceHealthParsedLastReceived => 'Dernière réception';

  @override
  String
  get maintenanceHealthParsedConfiguredValueDoesNotConfirmSynchronization =>
      'Valeur configurée (ne confirme pas la synchronisation)';

  @override
  String get maintenanceHealthParsedNoWarningRecorded =>
      'Aucune alerte enregistrée';

  @override
  String get maintenanceHealthParsedNotRecorded => 'Non enregistré';

  @override
  String get maintenanceHealthParsedACPower => 'Alimentation secteur';

  @override
  String get maintenanceHealthParsedBatteryPower => 'Sur batterie';

  @override
  String get maintenanceHealthParsedACConnected => 'Secteur connecté';

  @override
  String get maintenanceHealthParsedNotCharging => 'Ne charge pas';

  @override
  String get maintenanceHealthParsedCharging => 'En charge';

  @override
  String get maintenanceHealthParsedDischarging => 'En décharge';

  @override
  String get maintenanceHealthParsedCharged => 'Chargée';

  @override
  String get maintenanceHealthParsedStillLoggedIn => 'Toujours connecté';

  @override
  String get maintenanceHealthParsedYes => 'Oui';

  @override
  String get maintenanceHealthParsedNo => 'Non';

  @override
  String get maintenanceHealthParsedArchitectureField => 'Architecture';

  @override
  String get maintenanceHealthParsedKernelName => 'Nom du noyau';

  @override
  String get maintenanceHealthParsedKernelVersion => 'Version du noyau';

  @override
  String get maintenanceHealthParsedHostname => 'Nom d’hôte';

  @override
  String get maintenanceHealthParsedBatteryPresent => 'Batterie présente';

  @override
  String get maintenanceHealthParsedMinimumCharacters => 'Caractères minimum';

  @override
  String get maintenanceHealthParsedBatteryCycles => 'Cycles de batterie';

  @override
  String get maintenanceHealthParsedDesignCapacityMAh =>
      'Capacité nominale (mAh)';

  @override
  String get maintenanceHealthParsedVoltageMV => 'Tension (mV)';

  @override
  String get maintenanceHealthParsedLogonSessionID => 'ID de session';

  @override
  String get maintenanceHealthParsedLogonTypeCode =>
      'Code du type de connexion';

  @override
  String get maintenanceHealthParsedStartTime => 'Heure de début';

  @override
  String get maintenanceHealthParsedLastBootTime => 'Dernier démarrage';

  @override
  String get maintenanceHealthParsedAccountDisabled => 'Compte désactivé';

  @override
  String get maintenanceHealthParsedAccountLocked => 'Compte verrouillé';

  @override
  String get maintenanceHealthParsedPasswordRequired => 'Mot de passe requis';

  @override
  String get maintenanceHealthParsedPasswordExpires => 'Mot de passe expirant';

  @override
  String get maintenanceHealthParsedBatteryStatusCode =>
      'Code d’état de batterie';

  @override
  String get maintenanceHealthParsedRemainingCharge => 'Charge restante (%)';

  @override
  String get maintenanceHealthParsedEstimatedRuntimeMin =>
      'Autonomie estimée (min)';

  @override
  String get maintenanceHealthParsedLocalDateAndTime => 'Date et heure locales';

  @override
  String get maintenanceHealthParsedUTCOffsetMin => 'Décalage UTC (min)';

  @override
  String get maintenanceHealthParsedStandardTimeZone => 'Fuseau standard';

  @override
  String get maintenanceHealthParsedDaylightTimeZone => 'Fuseau d’été';

  @override
  String get maintenanceHealthParsedUTCCorrectionMin => 'Correction UTC (min)';

  @override
  String get maintenanceHealthParsedLastPasswordChange =>
      'Dernière modification du mot de passe';

  @override
  String get maintenanceHealthParsedPasswordExpiry =>
      'Expiration du mot de passe';

  @override
  String get maintenanceHealthParsedPasswordInactivityDate =>
      'Inactivité du mot de passe';

  @override
  String get maintenanceHealthParsedAccountExpiry => 'Expiration du compte';

  @override
  String get maintenanceHealthParsedMinimumPasswordAgeDays =>
      'Durée minimale (jours)';

  @override
  String get maintenanceHealthParsedMaximumPasswordAgeDays =>
      'Durée maximale (jours)';

  @override
  String get maintenanceHealthParsedPasswordExpiryWarningDays =>
      'Avertissement (jours)';

  @override
  String get maintenanceHealthParsedReferenceClockID =>
      'ID d’horloge de référence';

  @override
  String get maintenanceHealthParsedReferenceTimeUTC =>
      'Heure de référence (UTC)';

  @override
  String get maintenanceHealthParsedSystemClockOffset =>
      'Écart de l’horloge système';

  @override
  String get maintenanceHealthParsedLastOffset => 'Dernier décalage';

  @override
  String get maintenanceHealthParsedRMSOffset => 'Décalage RMS';

  @override
  String get maintenanceHealthParsedFrequencyError => 'Erreur de fréquence';

  @override
  String get maintenanceHealthParsedResidualFrequency => 'Fréquence résiduelle';

  @override
  String get maintenanceHealthParsedFrequencySkew => 'Dérive de fréquence';

  @override
  String get maintenanceHealthParsedRootDelay => 'Délai racine';

  @override
  String get maintenanceHealthParsedRootDispersion => 'Dispersion racine';

  @override
  String get maintenanceHealthParsedUpdateInterval =>
      'Intervalle de mise à jour';

  @override
  String get maintenanceHealthParsedLeapStatus => 'État intercalaire';

  @override
  String get maintenanceHealthParsedLastRotation => 'Dernière rotation';

  @override
  String get maintenanceHealthParsedRetainedCopies => 'Copies conservées';

  @override
  String get maintenanceHealthParsedSizeThreshold => 'Seuil de taille';

  @override
  String get maintenanceHealthParsedRotationSchedule => 'Plan de rotation';

  @override
  String get maintenanceHealthParsedDailyRotation => 'Rotation quotidienne';

  @override
  String get maintenanceHealthParsedWeeklyRotation => 'Rotation hebdomadaire';

  @override
  String get maintenanceHealthParsedMonthlyRotation => 'Rotation mensuelle';

  @override
  String get maintenanceHealthParsedRetainedCopiesField => 'Copies conservées';

  @override
  String get maintenanceHealthParsedCompressArchives =>
      'Compresser les archives';

  @override
  String get maintenanceHealthParsedDelayCompression => 'Compression différée';

  @override
  String get maintenanceHealthParsedAllowMissingLogs =>
      'Autoriser les journaux absents';

  @override
  String get maintenanceHealthParsedSkipEmptyLogs =>
      'Ignorer les journaux vides';

  @override
  String get maintenanceHealthParsedNewLogModeAndOwner =>
      'Mode et propriétaire du nouveau journal';

  @override
  String get maintenanceHealthParsedPostRotationScript =>
      'Script après rotation';

  @override
  String get maintenanceHealthParsedSharedRotationScripts =>
      'Scripts de rotation partagés';

  @override
  String get maintenanceHealthParsedIncludedRules => 'Règles incluses';

  @override
  String get maintenanceHealthParsedSizeThresholdField => 'Seuil de taille';

  @override
  String get maintenanceHealthParsedPAMAuthentication => 'Authentification PAM';

  @override
  String get maintenanceHealthParsedAllowedUsers => 'Utilisateurs autorisés';

  @override
  String get maintenanceHealthParsedDeniedUsers => 'Utilisateurs refusés';

  @override
  String get maintenanceHealthParsedAllowedGroups => 'Groupes autorisés';

  @override
  String get maintenanceHealthParsedDeniedGroups => 'Groupes refusés';

  @override
  String get maintenanceHealthParsedPasswordSet => 'Mot de passe défini';

  @override
  String get maintenanceHealthParsedPasswordLocked => 'Mot de passe verrouillé';

  @override
  String get maintenanceHealthParsedPasswordEmpty => 'Aucun mot de passe';

  @override
  String get maintenanceHealthParsedNever => 'Jamais';

  @override
  String get maintenanceHealthParsedConfigured => 'Configuré';

  @override
  String get maintenanceGpuComponents => 'Composants GPU et diagnostics';

  @override
  String get maintenanceGpuFields => 'Mesures et métadonnées';

  @override
  String get maintenanceGpuProbeUnavailable =>
      'Données partiellement indisponibles ou incomplètes';

  @override
  String get maintenanceGpuCudaCompatibility =>
      'Version CUDA prise en charge par le pilote';

  @override
  String get maintenanceGpuDetailFabric => 'État Fabric';

  @override
  String get maintenanceGpuDetailMemory => 'Mémoire vidéo';

  @override
  String get maintenanceGpuDetailEcc => 'Compteurs d’erreurs ECC';

  @override
  String get maintenanceGpuDetailThrottling =>
      'Causes de limitation de fréquence';

  @override
  String get maintenanceGpuDetailUtilization => 'Utilisation des moteurs';

  @override
  String get maintenanceGpuDetailRestarts => 'Redémarrages du service';

  @override
  String get maintenanceGpuDetailLoaded => 'État de chargement du service';

  @override
  String get maintenanceGpuDetailDetailState => 'État détaillé';

  @override
  String get maintenanceGpuDetailResult => 'Résultat de la dernière exécution';

  @override
  String get maintenanceGpuDetailCpuTime => 'Temps CPU cumulé (ns)';

  @override
  String get maintenanceGpuDetailLinkCounters =>
      'Compteurs d’erreurs cumulés NVLink';

  @override
  String get maintenanceGpuDetailAttached => 'GPU connectés';

  @override
  String get maintenanceLogArchives => 'Historique de rotation';

  @override
  String get maintenanceLogPolicy => 'Règles de rotation';

  @override
  String get maintenanceAccountGroup => 'Groupe';

  @override
  String get maintenancePosixShell => 'Shell POSIX';

  @override
  String get maintenancePowerShell => 'PowerShell';

  @override
  String get maintenanceCmdShell => 'CMD';

  @override
  String get maintenanceWindowsScm => 'Gestionnaire de services Windows';

  @override
  String get maintenanceGpuUuid => 'Identifiant GPU';

  @override
  String get maintenanceDeviceIdentity => 'Identifiant de l’appareil';

  @override
  String get maintenanceGpuMetal => 'Prise en charge Metal';

  @override
  String get maintenanceGpuSourceNvidia => 'Collecte NVIDIA';

  @override
  String get maintenanceGpuSourceDrm => 'DRM du noyau';

  @override
  String get maintenanceGpuSourceApple => 'Rapport système';

  @override
  String get maintenanceGpuSourceWindows => 'WMI';

  @override
  String get maintenanceGpuSerial => 'Numéro de série';

  @override
  String get maintenanceGpuPerformanceState => 'État de performance';

  @override
  String get maintenanceGpuVbios => 'Version VBIOS';

  @override
  String get maintenanceGpuBoardId => 'Identifiant de carte';

  @override
  String get maintenanceGpuPartNumber => 'Référence';

  @override
  String get maintenanceGpuInforom => 'Version InfoROM';

  @override
  String get maintenanceGpuEncoder => 'Utilisation encodeur';

  @override
  String get maintenanceGpuDecoder => 'Utilisation décodeur';

  @override
  String get maintenanceGpuMemoryUtil => 'Utilisation VRAM';

  @override
  String get maintenanceGpuProductBrand => 'Gamme de produits';

  @override
  String get maintenanceHealthy => 'Sain';

  @override
  String get maintenanceMacos => 'macOS';

  @override
  String get maintenanceBusBuiltin => 'Intégré';

  @override
  String get maintenanceLoadAddress => 'Adresse de chargement';

  @override
  String get maintenanceLaunchd => 'Services de lancement';

  @override
  String get maintenanceColorLcd => 'LCD couleur';

  @override
  String get maintenanceChargeState => 'État de charge';

  @override
  String get maintenanceToolSysctl => 'Paramètres noyau';

  @override
  String get maintenanceToolTop => 'Échantillon de processus';

  @override
  String get maintenanceToolVmStat => 'Mémoire virtuelle';

  @override
  String get maintenanceToolIoreg => 'Arborescence matérielle';

  @override
  String get maintenanceToolNetstat => 'Connexions réseau';

  @override
  String get maintenanceToolLaunchctl => 'Éléments de démarrage';

  @override
  String get maintenanceTransactions => 'Transactions';

  @override
  String get maintenanceSessionType => 'Type de session';

  @override
  String get maintenanceMachServices => 'Services Mach';

  @override
  String get maintenanceOnDemand => 'À la demande';

  @override
  String get maintenanceKeepAlive => 'Maintenir actif';

  @override
  String get maintenanceRunAtLoad => 'Lancer au chargement';

  @override
  String get maintenanceProcessType => 'Type de processus';

  @override
  String get maintenanceThrottle => 'Intervalle de limitation';

  @override
  String get maintenanceArguments => 'Arguments';

  @override
  String get maintenanceConsole => 'Console';

  @override
  String get maintenanceContainerTab => 'Conteneurs';

  @override
  String get maintenanceContainerAuto => 'Détection automatique';

  @override
  String get maintenanceContainerRuntime => 'Moteur de conteneurs';

  @override
  String get maintenanceContainerList => 'Conteneurs';

  @override
  String get maintenanceContainerPods => 'Pods';

  @override
  String get maintenanceContainerScope => 'Espace de noms';

  @override
  String get maintenanceContainerScopeDefault =>
      'Espace de noms (par défaut : default)';

  @override
  String get maintenanceContainerScopeAll => 'Espace de noms (vide : tous)';

  @override
  String get maintenanceContainerEndpoint =>
      'Point de terminaison CRI (vide : défaut)';

  @override
  String get maintenanceContainerSearch =>
      'Rechercher nom, image, espace de noms';

  @override
  String get maintenanceContainerContext => 'Contexte de connexion';

  @override
  String get maintenanceContainerNoRecords => 'Aucune entrée dans ce périmètre';

  @override
  String get maintenanceContainerMetrics => 'Mesures des ressources';

  @override
  String get maintenanceContainerMetadata => 'Métadonnées et état du moteur';

  @override
  String get maintenanceContainerSelect => 'Sélectionner un conteneur du pod';

  @override
  String get maintenanceContainerNoOperable =>
      'Aucun conteneur disponible dans ce pod. Actualisez et réessayez.';

  @override
  String get maintenanceContainerStateImpact =>
      'Cette opération modifie l’état du conteneur.';

  @override
  String get maintenanceContainerDeleteImpact =>
      'La suppression est irréversible. Les volumes montés sont conservés.';

  @override
  String get maintenanceContainerPodRecreated =>
      'Un contrôleur peut recréer le pod supprimé.';

  @override
  String get maintenanceContainerSubmitted =>
      'Opération envoyée. Actualisez pour voir l’état actuel.';

  @override
  String get maintenanceContainerFiles => 'Fichiers du conteneur';

  @override
  String get maintenanceContainerTerminal => 'Terminal interactif';

  @override
  String get maintenanceContainerConnecting =>
      'Connexion au terminal du conteneur…';

  @override
  String get maintenanceContainerTerminalClosed =>
      'Le terminal d’origine est fermé. Reconnectez-vous.';

  @override
  String get maintenanceContainerTerminalExited =>
      'Terminal du conteneur fermé.';

  @override
  String get maintenanceContainerTerminalEnded =>
      'Connexion terminée. Consultez la sortie du terminal.';

  @override
  String get maintenanceContainerStart => 'Démarrer';

  @override
  String get maintenanceContainerStop => 'Arrêter';

  @override
  String get maintenanceContainerRestart => 'Redémarrer';

  @override
  String get maintenanceContainerResume => 'Reprendre';

  @override
  String get maintenanceContainerEvents => 'Événements';

  @override
  String get maintenanceContainerReady => 'Prêt';

  @override
  String get maintenanceContainerPending => 'En attente';

  @override
  String get maintenanceContainerSucceeded => 'Terminé';

  @override
  String get maintenanceContainerTerminated => 'Terminé';

  @override
  String get maintenanceContainerCreated => 'Créé';

  @override
  String get maintenanceContainerRemoving => 'Suppression';

  @override
  String get maintenanceContainerRestarting => 'Redémarrage';

  @override
  String get maintenanceContainerNode => 'Nœud';

  @override
  String get maintenanceContainerVersion => 'Version du serveur';

  @override
  String get maintenanceContainerRunning => 'Conteneurs actifs';

  @override
  String get maintenanceContainerPaused => 'Conteneurs en pause';

  @override
  String get maintenanceContainerStopped => 'Conteneurs arrêtés';

  @override
  String get maintenanceContainerConfig => 'Configuration';

  @override
  String get maintenanceContainerHostConfig => 'Configuration de l’hôte';

  @override
  String get maintenanceContainerNetworkConfig => 'Configuration réseau';

  @override
  String get maintenanceContainerLabels => 'Étiquettes';

  @override
  String get maintenanceContainerAnnotations => 'Annotations';

  @override
  String get maintenanceContainerSpec => 'Spécification';

  @override
  String get maintenanceContainerMetadataFields => 'Métadonnées';

  @override
  String get maintenanceContainerConditions => 'Conditions';

  @override
  String get maintenanceContainerEnvironment => 'Variables d’environnement';

  @override
  String get maintenanceContainerEntrypoint => 'Point d’entrée';

  @override
  String get maintenanceContainerResources => 'Ressources';

  @override
  String get maintenanceContainerLimits => 'Limites de ressources';

  @override
  String get maintenanceContainerRequests => 'Demandes de ressources';

  @override
  String get maintenanceContainerVolumes => 'Volumes';

  @override
  String get maintenanceContainerEndpoints => 'Points de terminaison réseau';

  @override
  String get maintenanceContainerNetworks => 'Réseaux';

  @override
  String get maintenanceContainerDriver => 'Pilote de stockage';

  @override
  String get maintenanceContainerCgroupDriver => 'Pilote cgroup';

  @override
  String get maintenanceContainerDataDirectory => 'Répertoire de données';

  @override
  String get maintenanceContainerMemoryUsage => 'Mémoire utilisée / limite';

  @override
  String get maintenanceContainerNetworkIO => 'Réseau reçu / envoyé';

  @override
  String get maintenanceContainerBlockIO => 'Lecture / écriture bloc IO';

  @override
  String get maintenanceContainerProcesses => 'Processus';

  @override
  String get maintenanceContainerCpuUsage => 'Utilisation CPU';

  @override
  String get maintenanceContainerMemory => 'Mémoire utilisée';

  @override
  String get maintenanceContainerHealth => 'Contrôle de santé';

  @override
  String get maintenanceContainerImageId => 'ID de l’image';

  @override
  String get maintenanceContainerContainerId => 'ID du conteneur';

  @override
  String get maintenanceContainerOwner => 'Contrôleur propriétaire';

  @override
  String get maintenanceContainerMessage => 'Message de diagnostic';

  @override
  String get maintenanceContainerNoContext =>
      'Aucun contexte de connexion actuel trouvé.';

  @override
  String get maintenanceContainerPermissionTitle => 'Accès en lecture refusé';

  @override
  String get maintenanceContainerTimeoutTitle => 'Collecte expirée';

  @override
  String get maintenanceContainerConnectionTitle =>
      'Connexion au service indisponible';

  @override
  String get maintenanceContainerUnavailableTitle =>
      'Service de conteneurs indisponible';

  @override
  String get maintenanceContainerMissingTitle => 'Outil de collecte manquant';

  @override
  String get maintenanceContainerFormatTitle => 'Format du rapport non reconnu';

  @override
  String get maintenanceContainerDataTitle => 'Données indisponibles';

  @override
  String get maintenanceContainerPermissionHelp =>
      'Vérifiez les droits du compte et réessayez.';

  @override
  String get maintenanceContainerConnectionHelp =>
      'Vérifiez que le service est actif et contrôlez son adresse.';

  @override
  String get maintenanceContainerRuntimeHelp =>
      'Vérifiez le moteur sélectionné, son contexte et son point de terminaison.';

  @override
  String get maintenanceContainerTimeoutHelp =>
      'Vérifiez l’état du service et la connexion, puis réessayez.';

  @override
  String get maintenanceContainerMissingHelp =>
      'Installez l’outil requis et vérifiez sa disponibilité dans le terminal.';

  @override
  String get maintenanceContainerFormatHelp =>
      'Vérifiez la version de l’outil et le périmètre de collecte, puis réessayez.';

  @override
  String get maintenanceContainerDataHelp =>
      'Vérifiez le service, les droits et les outils, puis relancez la collecte.';

  @override
  String get maintenanceContainerClientVersion => 'Version du client';

  @override
  String get maintenanceContainerApiVersion => 'Version de l’API';

  @override
  String get maintenanceContainerGenericVersion => 'Version';

  @override
  String get maintenanceContainerInitContainers =>
      'Conteneurs d’initialisation';

  @override
  String get maintenanceContainerInitStatus =>
      'État des conteneurs d’initialisation';

  @override
  String get maintenanceContainerHostAddress => 'Adresse de l’hôte';

  @override
  String get maintenanceContainerRecords => 'Enregistrements';

  @override
  String get maintenanceContainerPlugins => 'Plugins';

  @override
  String get maintenanceContainerSecurity => 'Options de sécurité';

  @override
  String get maintenanceContainerWarnings => 'Avertissements';

  @override
  String get maintenanceContainerStartedAt => 'Démarré le';

  @override
  String get maintenanceContainerFinishedAt => 'Terminé le';

  @override
  String get maintenanceContainerOutOfMemory => 'Mémoire insuffisante';

  @override
  String get maintenanceContainerReason => 'Cause';

  @override
  String get maintenanceContainerResultCode => 'Code du résultat';

  @override
  String get maintenanceContainerResult => 'Résultat';

  @override
  String get maintenanceContainerConnectionAddress => 'Point de connexion';

  @override
  String get maintenanceContainerResourceStatus => 'État de la ressource';

  @override
  String get maintenanceContainerDiagnosticStatus => 'État du diagnostic';

  @override
  String get maintenanceContainerPermissionDenied =>
      'Droits de lecture insuffisants';

  @override
  String get maintenanceContainerResponseTimeout =>
      'Réponse de la cible expirée';

  @override
  String get maintenanceContainerResponseTimeoutShort => 'Réponse expirée';

  @override
  String get maintenanceContainerNotConnected => 'Connexion non établie';

  @override
  String get maintenanceContainerToolUnavailable => 'Outil requis indisponible';

  @override
  String get maintenanceContainerCollectionIncomplete => 'Collecte incomplète';

  @override
  String get maintenanceContainerSocketMissing =>
      'Fichier socket absent. Vérifiez que le service est actif.';

  @override
  String get maintenanceContainerDiagnosticFormat =>
      'Sortie partiellement non reconnue. Vérifiez la version de l’outil et le périmètre.';

  @override
  String get maintenanceContainerFileManager => 'Gestionnaire de fichiers';

  @override
  String get maintenanceContainerExit => 'Quitter';

  @override
  String get maintenanceContainerLogs => 'Journaux';

  @override
  String get maintenanceContainerDefaultRuntime => 'Moteur par défaut';

  @override
  String get maintenanceContainerRuntimes => 'Moteurs disponibles';

  @override
  String get maintenanceContainerLoggingDriver => 'Pilote de journalisation';

  @override
  String get maintenanceContainerCgroupVersion => 'Version cgroup';

  @override
  String get maintenanceContainerDriverStatus => 'État du pilote';

  @override
  String get maintenanceContainerRegistry => 'Configuration du registre';

  @override
  String get maintenanceContainerLiveRestore =>
      'Maintenir les conteneurs actifs pendant la reprise';

  @override
  String get maintenanceContainerLogPath => 'Chemin des journaux';

  @override
  String get maintenanceContainerPrivileged => 'Mode privilégié';

  @override
  String get maintenanceContainerReadOnlyRoot =>
      'Système de fichiers racine en lecture seule';

  @override
  String get maintenanceContainerAutoRemove =>
      'Suppression automatique à l’arrêt';

  @override
  String get maintenanceContainerNetworkMode => 'Mode réseau';

  @override
  String get maintenanceContainerPidMode => 'Mode d’espace de noms PID';

  @override
  String get maintenanceContainerIpcMode => 'Mode d’espace de noms IPC';

  @override
  String get maintenanceContainerCapabilitiesAdded => 'Capacités ajoutées';

  @override
  String get maintenanceContainerCapabilitiesDropped => 'Capacités retirées';

  @override
  String get maintenanceContainerCpuShares => 'Poids de planification CPU';

  @override
  String get maintenanceContainerNanoCpus => 'Quota CPU (nanocœurs)';

  @override
  String get maintenanceContainerMemoryReservation => 'Mémoire réservée';

  @override
  String get maintenanceContainerPublishedPorts => 'Ports exposés';

  @override
  String get maintenanceContainerImagePolicy =>
      'Politique de récupération d’image';

  @override
  String get maintenanceContainerServiceAccount => 'Compte de service';

  @override
  String get maintenanceContainerScheduler => 'Planificateur';

  @override
  String get maintenanceContainerNodeSelector => 'Sélecteur de nœud';

  @override
  String get maintenanceContainerSecurityContext => 'Contexte de sécurité';

  @override
  String get maintenanceContainerPodList => 'Liste des pods';

  @override
  String get maintenanceContainerNodeInfo => 'Informations du nœud';

  @override
  String get maintenanceContainerCompiler => 'Compilateur';

  @override
  String get maintenanceContainerGoVersion => 'Version de Go';

  @override
  String get maintenanceContainerGoroutines => 'Goroutines';

  @override
  String get maintenanceContainerPublishAllPorts => 'Publier tous les ports';

  @override
  String get maintenanceContainerLivenessProbe => 'Sonde de vitalité';

  @override
  String get maintenanceContainerReadinessProbe => 'Sonde de disponibilité';

  @override
  String get maintenanceContainerStartupProbe => 'Sonde de démarrage';

  @override
  String get maintenanceNetworkApplicationFirewall => 'Pare-feu applicatif';

  @override
  String get maintenanceNetworkListeners => 'Ports en écoute';

  @override
  String get maintenanceNetworkAdapters => 'Interfaces réseau';

  @override
  String get maintenanceNetworkProxySettings => 'Proxy réseau système';

  @override
  String get maintenanceNetworkFirewallStatus => 'État du pare-feu';

  @override
  String get maintenanceNetworkProtocolStats =>
      'Statistiques des protocoles et erreurs';

  @override
  String get maintenanceNetworkFirewallNat => 'Pare-feu et NAT';

  @override
  String get maintenanceNetworkTerminalEnvironment =>
      'Environnement du terminal';

  @override
  String get maintenanceNetworkDesktopProxy => 'Proxy du bureau';

  @override
  String get maintenanceNetworkSystemSettings => 'Paramètres système';

  @override
  String get maintenanceNetworkCurrentUser => 'Utilisateur actuel';

  @override
  String get maintenanceNetworkProxyMode => 'Mode proxy';

  @override
  String get maintenanceNetworkProxyState => 'État du proxy';

  @override
  String get maintenanceNetworkProxyServer => 'Serveur proxy';

  @override
  String get maintenanceNetworkProxyBypass => 'Exceptions proxy';

  @override
  String get maintenanceNetworkAutoDiscovery => 'Découverte automatique';

  @override
  String get maintenanceNetworkDirect => 'Connexion directe';

  @override
  String get maintenanceNetworkManual => 'Configuration manuelle';

  @override
  String get maintenanceNetworkAutomatic => 'Configuration automatique';

  @override
  String get maintenanceNetworkNoProxy =>
      'Aucune configuration proxy dans cette portée';

  @override
  String get maintenanceNetworkReceivePackets => 'Paquets reçus / s';

  @override
  String get maintenanceNetworkSendPackets => 'Paquets envoyés / s';

  @override
  String get maintenanceNetworkReceiveErrors => 'Erreurs de réception / s';

  @override
  String get maintenanceNetworkSendErrors => 'Erreurs d\'envoi / s';

  @override
  String get maintenanceNetworkReceiveDrops => 'Paquets reçus perdus / s';

  @override
  String get maintenanceNetworkSendDrops => 'Paquets envoyés perdus / s';

  @override
  String get maintenanceNetworkMacAddress => 'Adresse MAC';

  @override
  String get maintenanceNetworkProxyUnavailable =>
      'Paramètres du proxy de bureau indisponibles ; les variables du terminal ne représentent pas le proxy global.';

  @override
  String get maintenanceNetworkProxyAddress => 'Adresse du proxy';

  @override
  String get maintenanceNetworkProxyPort => 'Port du proxy';

  @override
  String get maintenanceNetworkPacAddress => 'URL PAC';

  @override
  String get maintenanceNetworkPacState => 'État PAC';

  @override
  String get maintenanceNetworkProxyLocalBypass => 'Ignorer les noms locaux';

  @override
  String get maintenanceNetworkProxyAuthentication => 'Authentification proxy';

  @override
  String get maintenanceNetworkProxyShared => 'Proxy partagé';

  @override
  String get maintenanceNetworkDomainProfile => 'Réseau de domaine';

  @override
  String get maintenanceNetworkPrivateProfile => 'Réseau privé';

  @override
  String get maintenanceNetworkPublicProfile => 'Réseau public';

  @override
  String get maintenanceNetworkActiveProfile => 'Profil actif';

  @override
  String get maintenanceNetworkDefaultInbound => 'Entrant par défaut';

  @override
  String get maintenanceNetworkDefaultOutbound => 'Sortant par défaut';

  @override
  String get maintenanceNetworkResolverStatus => 'État du résolveur';

  @override
  String get maintenanceNetworkBlock => 'Bloquer';

  @override
  String get maintenanceNetworkAllow => 'Autoriser';

  @override
  String get maintenanceNetCounterPacketsSent => 'Paquets envoyés';

  @override
  String get maintenanceNetCounterPacketsReceived => 'Paquets reçus';

  @override
  String maintenanceNetCounterDataPackets(String v0) {
    return 'Paquets de données ($v0 octets)';
  }

  @override
  String maintenanceNetCounterRetransmittedData(String v0) {
    return 'Paquets retransmis ($v0 octets)';
  }

  @override
  String get maintenanceNetCounterMtuResend =>
      'Retransmissions dues à la découverte MTU';

  @override
  String maintenanceNetCounterAckOnly(String v0) {
    return 'Paquets ACK seuls ($v0 retardés)';
  }

  @override
  String get maintenanceNetCounterUrgOnly => 'Paquets URG seuls';

  @override
  String get maintenanceNetCounterWindowProbe => 'Sondes de fenêtre';

  @override
  String get maintenanceNetCounterWindowUpdate => 'Mises à jour de fenêtre';

  @override
  String get maintenanceNetCounterControlPacket => 'Paquets de contrôle';

  @override
  String get maintenanceNetCounterAfterFlowControl =>
      'Paquets envoyés après contrôle de flux';

  @override
  String get maintenanceNetCounterChallengeSyn =>
      'ACK de vérification pour SYN inattendu';

  @override
  String get maintenanceNetCounterChallengeRst =>
      'ACK de vérification pour RST inattendu';

  @override
  String get maintenanceNetCounterSoftwareChecksum =>
      'Sommes de contrôle logicielles';

  @override
  String maintenanceNetCounterIpv4Segments(String v0) {
    return 'Segments IPv4 ($v0 octets)';
  }

  @override
  String maintenanceNetCounterIpv6Segments(String v0) {
    return 'Segments IPv6 ($v0 octets)';
  }

  @override
  String maintenanceNetCounterAcknowledgments(String v0) {
    return 'Accusés de réception ($v0 octets)';
  }

  @override
  String get maintenanceNetCounterDuplicateAck =>
      'Accusés de réception en double';

  @override
  String get maintenanceNetCounterUnsentAck =>
      'Accusés pour données non envoyées';

  @override
  String maintenanceNetCounterInSequence(String v0) {
    return 'Paquets reçus dans l’ordre ($v0 octets)';
  }

  @override
  String maintenanceNetCounterDuplicatePacket(String v0) {
    return 'Paquets entièrement dupliqués ($v0 octets)';
  }

  @override
  String get maintenanceNetCounterOldDuplicate => 'Anciens paquets dupliqués';

  @override
  String get maintenanceNetCounterReceiveNoMemory =>
      'Paquets reçus perdus faute de mémoire';

  @override
  String maintenanceNetCounterPartialDuplicate(String v0) {
    return 'Paquets partiellement dupliqués ($v0 octets)';
  }

  @override
  String maintenanceNetCounterOutOfOrder(String v0) {
    return 'Paquets hors ordre ($v0 octets)';
  }

  @override
  String maintenanceNetCounterBeyondWindow(String v0) {
    return 'Paquets au-delà de la fenêtre ($v0 octets)';
  }

  @override
  String get maintenanceNetCounterRecoveredLoss =>
      'Paquets récupérés après perte';

  @override
  String get maintenanceNetCounterAfterClose => 'Paquets reçus après fermeture';

  @override
  String get maintenanceNetCounterBadReset => 'Réinitialisations invalides';

  @override
  String get maintenanceNetCounterBadChecksumDiscard =>
      'Paquets rejetés pour somme de contrôle invalide';

  @override
  String get maintenanceNetCounterBadChecksum => 'Erreurs de somme de contrôle';

  @override
  String get maintenanceNetCounterBadHeaderOffset =>
      'Paquets rejetés pour décalage d’en-tête invalide';

  @override
  String get maintenanceNetCounterTooShort => 'Paquets trop courts rejetés';

  @override
  String get maintenanceNetCounterConnectionRequests => 'Demandes de connexion';

  @override
  String get maintenanceNetCounterConnectionAccepts => 'Connexions acceptées';

  @override
  String get maintenanceNetCounterBadConnection =>
      'Tentatives de connexion échouées';

  @override
  String get maintenanceNetCounterListenOverflow =>
      'Débordements de file d’écoute';

  @override
  String get maintenanceNetCounterEstablished =>
      'Connexions établies (y compris acceptées)';

  @override
  String maintenanceNetCounterClosedConnections(String v0) {
    return 'Connexions fermées ($v0 abandonnées)';
  }

  @override
  String get maintenanceNetCounterRetransmitTimeout =>
      'Délais de retransmission expirés';

  @override
  String get maintenanceNetCounterPersistTimeout =>
      'Expirations du temporisateur de persistance';

  @override
  String get maintenanceNetCounterKeepaliveTimeout =>
      'Délais de maintien expirés';

  @override
  String get maintenanceNetCounterKeepaliveProbe =>
      'Sondes de maintien envoyées';

  @override
  String get maintenanceNetCounterIcmpError =>
      'Appels au gestionnaire d’erreurs ICMP';

  @override
  String get maintenanceNetCounterIcmpSuppressed =>
      'Erreurs supprimées pour erreur ICMP existante';

  @override
  String get maintenanceNetCounterIcmpRateLimit =>
      'Erreurs supprimées par limitation de débit';

  @override
  String get maintenanceNetCounterNoRoute => 'Aucune route';

  @override
  String get maintenanceNetCounterAdminProhibited =>
      'Interdit administrativement';

  @override
  String get maintenanceNetCounterBeyondScope => 'Hors portée';

  @override
  String get maintenanceNetCounterAddressUnreachable => 'Adresse inaccessible';

  @override
  String get maintenanceNetCounterPortUnreachable => 'Port inaccessible';

  @override
  String get maintenanceNetCounterPacketTooBig => 'Paquet trop volumineux';

  @override
  String get maintenanceNetCounterTransitExceeded => 'Temps de transit dépassé';

  @override
  String get maintenanceNetCounterReassemblyExceeded =>
      'Délai de réassemblage dépassé';

  @override
  String get maintenanceNetCounterHeaderError => 'Champ d’en-tête invalide';

  @override
  String get maintenanceNetCounterUnknownNextHeader =>
      'En-tête suivant inconnu';

  @override
  String get maintenanceNetCounterUnknownOption => 'Option inconnue';

  @override
  String get maintenanceNetCounterRedirect => 'Redirections';

  @override
  String get maintenanceNetCounterUnknown => 'Inconnu';

  @override
  String get maintenanceNetCounterUnreachable => 'Destination inaccessible';

  @override
  String get maintenanceNetCounterEcho => 'Requêtes d’écho';

  @override
  String get maintenanceNetCounterEchoReply => 'Réponses d’écho';

  @override
  String get maintenanceNetCounterRouterSolicit => 'Sollicitations de routeur';

  @override
  String get maintenanceNetCounterRouterAdvert => 'Annonces de routeur';

  @override
  String get maintenanceNetCounterNeighborSolicit => 'Sollicitations de voisin';

  @override
  String get maintenanceNetCounterNeighborAdvert => 'Annonces de voisin';

  @override
  String get maintenanceNetCounterMulticastQuery =>
      'Requêtes d’écoute multicast';

  @override
  String get maintenanceNetCounterMldReport => 'Rapports d’écoute MLDv2';

  @override
  String get maintenanceNetCounterBadCode => 'Messages avec codes invalides';

  @override
  String get maintenanceNetCounterShortMessage => 'Messages trop courts';

  @override
  String get maintenanceNetCounterBadLength => 'Messages de longueur invalide';

  @override
  String get maintenanceNetCounterResponses => 'Réponses générées';

  @override
  String get maintenanceNetCounterDatagramsReceived => 'Datagrammes reçus';

  @override
  String get maintenanceNetCounterDatagramsSent => 'Datagrammes envoyés';

  @override
  String get maintenanceNetCounterIncompleteHeader => 'En-têtes incomplets';

  @override
  String get maintenanceNetCounterBadDataLength =>
      'Champs de longueur invalides';

  @override
  String get maintenanceNetCounterNoChecksum =>
      'Paquets sans somme de contrôle';

  @override
  String get maintenanceNetCounterNoSocket =>
      'Rejets sans socket correspondant';

  @override
  String get maintenanceNetCounterFullSocket =>
      'Rejets pour tampons de socket pleins';

  @override
  String get maintenanceNetCounterDelivered => 'Paquets livrés';

  @override
  String maintenanceNetCounterIpv4Datagrams(String v0) {
    return 'Datagrammes IPv4 ($v0 octets)';
  }

  @override
  String maintenanceNetCounterIpv6Datagrams(String v0) {
    return 'Datagrammes IPv6 ($v0 octets)';
  }

  @override
  String get maintenanceNetCounterTotalReceived => 'Total des paquets reçus';

  @override
  String get maintenanceNetCounterFragmentsReceived => 'Fragments reçus';

  @override
  String get maintenanceNetCounterReassembled => 'Réassemblages réussis';

  @override
  String get maintenanceNetCounterForHost => 'Paquets destinés à cet hôte';

  @override
  String get maintenanceNetCounterFromHost => 'Paquets envoyés par cet hôte';

  @override
  String get maintenanceNetCounterForwarded => 'Paquets transférés';

  @override
  String get maintenanceNetCounterNotForwardable => 'Paquets non transférables';

  @override
  String get maintenanceNetCounterRedirectSent => 'Redirections envoyées';

  @override
  String get maintenanceNetCounterOpenTcp => 'Sockets TCP ouverts';

  @override
  String get maintenanceNetCounterOpenRaw => 'Sockets IP bruts ouverts';

  @override
  String get maintenanceNetCounterOpenLocal => 'Sockets locaux ouverts';

  @override
  String get maintenanceNetCounterActiveOpens => 'Ouvertures actives';

  @override
  String get maintenanceNetCounterPassiveOpens => 'Ouvertures passives';

  @override
  String get maintenanceNetCounterAttemptFails =>
      'Tentatives de connexion échouées';

  @override
  String get maintenanceNetCounterEstablishedResets =>
      'Connexions établies réinitialisées';

  @override
  String get maintenanceNetCounterCurrentEstablished =>
      'Connexions actuellement établies';

  @override
  String get maintenanceNetCounterInSegments => 'Segments reçus';

  @override
  String get maintenanceNetCounterOutSegments => 'Segments envoyés';

  @override
  String get maintenanceNetCounterRetransSegments => 'Segments retransmis';

  @override
  String get maintenanceNetCounterInputErrors => 'Erreurs d’entrée';

  @override
  String get maintenanceNetCounterOutputResets => 'Réinitialisations envoyées';

  @override
  String get maintenanceNetCounterInputPackets => 'Paquets entrants';

  @override
  String get maintenanceNetCounterInputDeliveries => 'Livraisons entrantes';

  @override
  String get maintenanceNetCounterOutputRequests => 'Requêtes sortantes';

  @override
  String get maintenanceNetCounterInputDiscards => 'Rejets entrants';

  @override
  String get maintenanceNetCounterOutputDiscards => 'Rejets sortants';

  @override
  String get maintenanceNetCounterUnknownProtocols =>
      'Protocoles entrants inconnus';

  @override
  String get maintenanceNetCounterInputHeaderErrors =>
      'Erreurs d’en-tête entrant';

  @override
  String get maintenanceNetCounterInputAddressErrors =>
      'Erreurs d’adresse entrante';

  @override
  String get maintenanceNetCounterOutputNoRoutes => 'Sorties sans route';

  @override
  String get maintenanceNetCounterInputDatagrams => 'Datagrammes reçus';

  @override
  String get maintenanceNetCounterOutputDatagrams => 'Datagrammes envoyés';

  @override
  String get maintenanceNetCounterNoPorts => 'Datagrammes sans port d’écoute';

  @override
  String get maintenanceNetCounterReceiveBufferErrors =>
      'Erreurs de tampon de réception';

  @override
  String get maintenanceNetCounterSendBufferErrors =>
      'Erreurs de tampon d’envoi';

  @override
  String get maintenanceNetCounterInputChecksumErrors =>
      'Erreurs de somme de contrôle entrante';

  @override
  String get maintenanceNetCounterReassemblyRequests =>
      'Demandes de réassemblage';

  @override
  String get maintenanceNetCounterReassemblyOk => 'Réassemblages réussis';

  @override
  String get maintenanceNetCounterReassemblyFails => 'Échecs de réassemblage';

  @override
  String get maintenanceNetCounterFragmentOk => 'Fragmentations réussies';

  @override
  String get maintenanceNetCounterFragmentFails => 'Échecs de fragmentation';

  @override
  String get maintenanceNetCounterFragmentsCreated => 'Fragments créés';

  @override
  String get maintenanceNetCounterListenDrops => 'Rejets de file d’écoute';

  @override
  String get maintenanceNetCounterListenOverflows =>
      'Débordements de file d’écoute';

  @override
  String get maintenanceNetCounterInputMessages => 'Messages reçus';

  @override
  String get maintenanceNetCounterOutputMessages => 'Messages envoyés';

  @override
  String get maintenanceNetCounterInUse => 'Sockets utilisés';

  @override
  String get maintenanceNetCounterOrphan => 'Sockets orphelins';

  @override
  String get maintenanceNetCounterTimeWait => 'Sockets en attente de fermeture';

  @override
  String get maintenanceNetCounterAllocated => 'Sockets alloués';

  @override
  String get maintenanceNetCounterMemoryPages => 'Pages mémoire';

  @override
  String maintenanceReadoutUnknownMetric(String index) {
    return 'Mesure supplémentaire $index';
  }

  @override
  String maintenanceReadoutUnknownGroup(String index) {
    return 'Statistiques supplémentaires $index';
  }

  @override
  String maintenanceReadoutRawMetric(String field) {
    return 'Champ d’origine : $field';
  }

  @override
  String get maintenanceReadoutInputHistogram => 'Types de messages reçus';

  @override
  String get maintenanceReadoutOutputHistogram => 'Types de messages envoyés';

  @override
  String get maintenanceReadoutErrorHistogram => 'Types d’erreurs générées';

  @override
  String maintenanceReadoutProtocolStats(String protocol) {
    return 'Statistiques $protocol';
  }

  @override
  String get maintenanceReadoutFabricManager =>
      'Service de gestion d’interconnexion GPU';

  @override
  String get maintenanceReadoutSuccess => 'Réussi';

  @override
  String get maintenanceReadoutNotFound => 'Introuvable';

  @override
  String get maintenanceReadoutActivating => 'Démarrage';

  @override
  String get maintenanceReadoutDeactivating => 'Arrêt en cours';

  @override
  String get maintenanceReadoutReloading => 'Rechargement';

  @override
  String get maintenanceReadoutNotApplicable => 'Sans objet';

  @override
  String get maintenanceReadoutNotSupported => 'Non pris en charge';

  @override
  String get maintenanceReadoutAborted => 'Interrompu';

  @override
  String get maintenanceReadoutMetric => 'Indicateur';

  @override
  String get maintenanceReadoutTotal => 'Total';

  @override
  String get maintenanceReadoutFree => 'Libre';

  @override
  String get maintenanceReadoutCurrent => 'Actuel';

  @override
  String get maintenanceReadoutSupported => 'Prise en charge';

  @override
  String get maintenanceReadoutPersistence => 'Mode persistant';

  @override
  String get maintenanceReadoutAccounting => 'Mode de comptabilisation';

  @override
  String get maintenanceReadoutDisplayActive => 'Affichage actif';

  @override
  String get maintenanceReadoutSingleBit => 'Erreurs sur un bit';

  @override
  String get maintenanceReadoutDoubleBit => 'Erreurs sur deux bits';

  @override
  String get maintenanceReadoutCorrectable => 'Erreurs corrigibles';

  @override
  String get maintenanceReadoutUncorrectable => 'Erreurs non corrigibles';

  @override
  String get maintenanceReadoutVolatile => 'Depuis le chargement du pilote';

  @override
  String get maintenanceReadoutAggregate => 'Cumul sur la durée de vie';

  @override
  String get maintenanceReadoutRetiredPages => 'Pages retirées';

  @override
  String get maintenanceReadoutRemappedRows => 'Lignes remappées';

  @override
  String get maintenanceReadoutMig => 'Mode GPU multi-instance';

  @override
  String get maintenanceReadoutClocks => 'Fréquences d’horloge';

  @override
  String get maintenanceReadoutMaxClocks => 'Fréquences maximales';

  @override
  String get maintenanceReadoutTemperatureLimit => 'Limite de température';

  @override
  String get maintenanceReadoutGpuIdle => 'GPU au repos';

  @override
  String get maintenanceReadoutThermalSlowdown => 'Limitation thermique';

  @override
  String get maintenanceReadoutPowerCap => 'Plafond de puissance';

  @override
  String get maintenanceReadoutHardwareSlowdown => 'Limitation matérielle';

  @override
  String get maintenanceReadoutServiceResult => 'Résultat d’exécution';

  @override
  String get maintenanceReadoutBind => 'Lié';

  @override
  String get maintenanceReadoutTentative => 'Provisoire';

  @override
  String get maintenanceReadoutPreferred => 'Préféré';

  @override
  String get maintenanceReadoutDeprecated => 'Obsolète';

  @override
  String get maintenanceReadoutDormant => 'Dormant';

  @override
  String get maintenanceReadoutRestartAlways => 'Toujours redémarrer';

  @override
  String get maintenanceReadoutRestartNever => 'Ne pas redémarrer';

  @override
  String get maintenanceReadoutRestartSuccess => 'Redémarrer en cas de succès';

  @override
  String get maintenanceReadoutRestartFailure => 'Redémarrer en cas d’échec';

  @override
  String get maintenanceReadoutRestartAbnormal =>
      'Redémarrer après sortie anormale';

  @override
  String get maintenanceReadoutRestartWatchdog =>
      'Redémarrer après expiration du watchdog';

  @override
  String get maintenanceReadoutRestartAbort => 'Redémarrer après interruption';

  @override
  String get maintenanceReadoutNotifyMain => 'Processus principal uniquement';

  @override
  String get maintenanceReadoutNotifyAll => 'Tous les processus';

  @override
  String get maintenanceReadoutNotifyExec => 'Processus exécutés';

  @override
  String get maintenanceReadoutKernelEvents => 'Événements du noyau';

  @override
  String get maintenanceReadoutKernelControl => 'Contrôle du noyau';

  @override
  String get maintenanceReadoutNetworkMonitoring => 'Surveillance réseau';

  @override
  String get maintenanceReadoutBackgroundSockets =>
      'Sockets inactifs en arrière-plan';

  @override
  String get maintenanceReadoutNetworkApi => 'Statistiques de l’API réseau';

  @override
  String get maintenanceReadoutWakePorts => 'Statistiques des ports de réveil';

  @override
  String get maintenanceReadoutDropReasons => 'Motifs de rejet des paquets';

  @override
  String get maintenanceReadoutPortOffload => 'Déchargement des ports locaux';

  @override
  String get maintenanceReadoutMbuf => 'Statistiques des tampons de paquets';

  @override
  String get maintenanceReadoutMultiMbuf => 'Tampons de paquets multiples';

  @override
  String get maintenanceTaskTitle => 'Tâches planifiées';

  @override
  String get maintenanceTaskAdd => 'Ajouter une tâche planifiée';

  @override
  String get maintenanceTaskEdit => 'Modifier la tâche planifiée';

  @override
  String get maintenanceTaskSearch =>
      'Rechercher tâches, commandes, utilisateurs';

  @override
  String get maintenanceTaskEmpty => 'Aucune tâche planifiée dans cette portée';

  @override
  String get maintenanceTaskScheduled => 'Configurée';

  @override
  String get maintenanceTaskReady => 'Prête';

  @override
  String get maintenanceTaskQueued => 'En attente';

  @override
  String get maintenanceTaskEnabled => 'Activée';

  @override
  String get maintenanceTaskDisabled => 'Désactivée';

  @override
  String get maintenanceTaskAll => 'Tous les ordonnanceurs';

  @override
  String get maintenanceTaskScheduler => 'Ordonnanceur';

  @override
  String get maintenanceTaskWindows => 'Planificateur de tâches Windows';

  @override
  String get maintenanceTaskSchedule => 'Planification';

  @override
  String get maintenanceTaskLast => 'Dernière exécution';

  @override
  String get maintenanceTaskNext => 'Prochaine exécution';

  @override
  String get maintenanceTaskSampled => 'Collectée le';

  @override
  String get maintenanceTaskNative => 'Configuration native';

  @override
  String get maintenanceTaskEnvironment => 'Environnement d’exécution';

  @override
  String get maintenanceTaskReadOnly =>
      'Cette configuration est en lecture seule ou non modifiable par cet utilisateur';

  @override
  String get maintenanceTaskDeleteConfirm =>
      'Supprimer cette tâche ? Sa configuration sera supprimée et les exécutions futures ne seront plus planifiées.';

  @override
  String get maintenanceTaskSaveConfirm =>
      'L’enregistrement met à jour la planification de la machine cible. Les minuteurs natifs chargés seront rechargés.';

  @override
  String get maintenanceTaskConflict =>
      'La tâche a été modifiée par un autre programme. Actualisez avant de la modifier.';

  @override
  String get maintenanceTaskValidation =>
      'Vérifiez la planification, la commande et le format de configuration.';

  @override
  String get maintenanceTaskBusy =>
      'Une modification est déjà en cours pour cet utilisateur. Réessayez bientôt.';

  @override
  String get maintenanceTaskLimit =>
      'La limite de collecte a été atteinte ; la liste peut être incomplète.';

  @override
  String get maintenanceTaskUnavailable =>
      'Ordonnanceur ou données associées indisponibles';

  @override
  String get maintenanceTaskSaveFailed =>
      'La modification a échoué. Consultez l’erreur et actualisez pour vérifier l’état actuel.';

  @override
  String get maintenanceTaskVerify =>
      'La vérification après modification a échoué. Actualisez sans soumettre à nouveau.';

  @override
  String get maintenanceTaskRollback =>
      'La restauration est incomplète. Vérifiez immédiatement l’ordonnanceur cible.';

  @override
  String get maintenanceTaskCredentials =>
      'Cette tâche nécessite de nouveaux identifiants système. Modifiez-la dans le Planificateur de tâches de la machine cible.';

  @override
  String get maintenanceTaskChangedTarget =>
      'La cible du terminal a changé. Rouvrez le panneau de maintenance.';

  @override
  String get maintenanceTaskLogs => 'Journaux d’exécution';

  @override
  String get maintenanceTaskNoLogs => 'Aucun journal de tâche lisible';

  @override
  String get maintenanceTaskStale =>
      'Échec de l’actualisation. Les données précédentes sont conservées ; les actions reprendront après une actualisation réussie.';

  @override
  String get maintenanceTaskCron => 'Expression cron';

  @override
  String get maintenanceTaskStart =>
      'Heure de début (heure locale de la machine cible)';

  @override
  String get maintenanceTaskDays => 'Intervalle en jours';

  @override
  String get maintenanceTaskArguments => 'Arguments';

  @override
  String get maintenanceTaskWorkingDirectory => 'Répertoire de travail';

  @override
  String get maintenanceTaskMissed => 'Exécutions manquées';

  @override
  String get maintenanceTaskPersistent => 'Rattraper les exécutions manquées';

  @override
  String get maintenanceTaskAccuracy => 'Précision de planification';

  @override
  String get maintenanceTaskRandomDelay => 'Délai aléatoire';

  @override
  String get maintenanceTaskOverrides => 'Surcharges de configuration';

  @override
  String get maintenanceTaskMonotonic => 'Règles de déclenchement monotones';

  @override
  String get maintenanceTaskInterval => 'Intervalle d’exécution (secondes)';

  @override
  String get maintenanceTaskCalendar => 'Déclencheurs calendaires';

  @override
  String get maintenanceTaskRunAtLoad => 'Exécuter au chargement';

  @override
  String get maintenanceTaskKeepAlive => 'Maintenir en exécution';

  @override
  String get maintenanceTaskStdout => 'Journal de sortie standard';

  @override
  String get maintenanceTaskStderr => 'Journal d’erreur standard';

  @override
  String get maintenanceTaskLogon => 'Type de connexion';

  @override
  String get maintenanceTaskRunLevel => 'Niveau d’exécution';

  @override
  String get maintenanceTaskExecutionLimit => 'Durée maximale d’exécution';

  @override
  String get maintenanceTaskParallel => 'Politique d’instances multiples';

  @override
  String get maintenanceTaskBatteryStart => 'Ne pas démarrer sur batterie';

  @override
  String get maintenanceTaskBatteryStop =>
      'Arrêter lors du passage sur batterie';

  @override
  String get maintenanceTaskWake => 'Réveiller pour exécuter';

  @override
  String get maintenanceTaskDemand => 'Autoriser le démarrage manuel';

  @override
  String get maintenanceTaskHidden => 'Tâche masquée';

  @override
  String get maintenanceTaskNetworkRequired => 'Connexion réseau requise';

  @override
  String get maintenanceTaskIdle => 'Exécuter uniquement au repos';

  @override
  String get maintenanceTaskHardTerminate => 'Autoriser l’arrêt forcé';

  @override
  String get maintenanceTaskTriggerBoot => 'Au démarrage';

  @override
  String get maintenanceTaskTriggerLogon => 'À la connexion';

  @override
  String get maintenanceTaskTriggerEvent => 'Sur événement';

  @override
  String get maintenanceTaskTriggerTime => 'Déclencheur horaire';

  @override
  String get maintenanceTaskTriggerSession => 'Déclencheur d’état de session';

  @override
  String get maintenanceTaskNativeProperty => 'Propriété native';

  @override
  String get maintenanceTaskTotal => 'Total des tâches';

  @override
  String get maintenanceTaskInteractive =>
      'Exécuter uniquement si l’utilisateur est connecté';

  @override
  String get maintenanceTaskPassword => 'Connexion avec mot de passe';

  @override
  String get maintenanceTaskNoPassword => 'Connexion sans mot de passe';

  @override
  String get maintenanceTaskMixedLogon =>
      'Connexion interactive ou avec mot de passe';

  @override
  String get maintenanceTaskIgnoreNew => 'Ignorer les exécutions simultanées';

  @override
  String get maintenanceTaskParallelRuns => 'Exécuter en parallèle';

  @override
  String get maintenanceTaskStopExisting => 'Arrêter l’exécution précédente';

  @override
  String get maintenanceTaskLeastPrivilege => 'Privilèges standard';

  @override
  String get maintenanceTaskHighestPrivilege =>
      'Privilèges les plus élevés disponibles';

  @override
  String get maintenanceTaskAfterBoot => 'Après démarrage';

  @override
  String get maintenanceTaskAfterActive => 'Après activation';

  @override
  String get maintenanceTaskAfterStartup => 'Après lancement de l’ordonnanceur';

  @override
  String get maintenanceTaskAfterUnitActive => 'Après activation du service';

  @override
  String get maintenanceTaskAfterUnitInactive => 'Après arrêt du service';

  @override
  String get maintenanceTimeout => 'Délai maximal de collecte';

  @override
  String maintenanceTimeoutSeconds(String value) {
    return 'Délai $value s';
  }

  @override
  String maintenanceTimeoutMinutes(String value) {
    return 'Délai $value min';
  }

  @override
  String maintenanceTimeoutHours(String value) {
    return 'Délai $value h';
  }

  @override
  String get maintenanceHealthPartial =>
      'Certaines mesures sont indisponibles ; les données recueillies sont conservées.';

  @override
  String get maintenanceHealthUnsynchronized =>
      'L’horloge n’est pas synchronisée';

  @override
  String get maintenanceHealthSyncStatus => 'État de synchronisation actuel';

  @override
  String get maintenanceHealthMeasurementNotes => 'Détails des mesures';

  @override
  String get maintenanceHealthNativeTimedLimit =>
      'Le service système timed ne fournit ni la source sélectionnée ni le décalage de l’horloge.';

  @override
  String get maintenanceHealthConfiguredOnly =>
      'Seule la configuration est disponible ; la source sélectionnée, le décalage et l’état de synchronisation sont inconnus.';

  @override
  String get maintenanceHealthSntpNotes =>
      'Mesure jusqu’à 3 sources configurées sans modifier l’horloge. Les résultats SNTP n’indiquent pas la source sélectionnée par le système.';

  @override
  String get maintenanceServiceMetricsUnavailable =>
      'Certaines mesures des processus de service n’ont pas pu être recueillies. Actualisez pour réessayer.';

  @override
  String get maintenanceContainerInterrupt => 'Interrompre';

  @override
  String get maintenanceContainerDisconnecting => 'Fermeture…';

  @override
  String get maintenanceContainerExitPending =>
      'Le programme est toujours actif. Interrompez-le avant de quitter le terminal.';

  @override
  String get maintenanceContainerTerminalFailed =>
      'Échec de la connexion au terminal';

  @override
  String get maintenanceContainerCopyRun => 'Copier la commande run';

  @override
  String get maintenanceContainerImageDetails =>
      'Afficher les détails de l’image';

  @override
  String get maintenanceContainerRunCopied =>
      'Commande run copiée depuis la configuration actuelle';

  @override
  String get maintenanceContainerConfigInvalid =>
      'La configuration du conteneur est incomplète ou invalide. Actualisez puis réessayez.';

  @override
  String get maintenanceContainerRunUnsupported =>
      'Ce moteur ne permet pas de reconstituer une commande run autonome.';

  @override
  String maintenanceContainerRunIncomplete(String fields) {
    return 'Ces paramètres ne peuvent pas être reproduits fidèlement ; aucune commande copiée : $fields';
  }

  @override
  String get maintenanceContainerImageMissing =>
      'Le conteneur ne fournit aucune référence d’image valide. Actualisez puis réessayez.';

  @override
  String get maintenanceContainerIdentityChanged =>
      'Le conteneur a été remplacé ou supprimé. Actualisez puis réessayez.';

  @override
  String get maintenanceImageLayers => 'Historique de construction et couches';

  @override
  String get maintenanceImageHistoryUnavailable =>
      'Métadonnées chargées, mais l’historique de construction est indisponible.';

  @override
  String get maintenanceImageHistoryLimited =>
      'Affichage des 512 dernières étapes de construction.';

  @override
  String get maintenanceImageReferenceOnly =>
      'L’API Kubernetes fournit uniquement les références d’image et l’état du conteneur. Consultez les couches et l’historique via le moteur du nœud concerné.';

  @override
  String get maintenanceImageTags => 'Étiquettes de l’image';

  @override
  String get maintenanceImageDigests => 'Empreintes de l’image';

  @override
  String get maintenanceImageSize => 'Taille de l’image';

  @override
  String get maintenanceImageBuildCommand => 'Instruction de construction';

  @override
  String get maintenanceImageLayerSize => 'Taille de la couche';

  @override
  String get maintenanceImageMetadata => 'Métadonnées de l’image';

  @override
  String get maintenanceImageRootFilesystem => 'Système de fichiers de l’image';

  @override
  String get maintenanceContainerLastStarted => 'Dernier démarrage';

  @override
  String get maintenanceImages => 'Images';

  @override
  String get maintenanceVolumes => 'Volumes';

  @override
  String get maintenanceContainerCreate => 'Créer un conteneur';

  @override
  String get maintenanceImagePull => 'Télécharger une image';

  @override
  String get maintenanceImageRemove => 'Supprimer l’image';

  @override
  String get maintenanceVolumeCreate => 'Créer un volume';

  @override
  String get maintenanceVolumeRemove => 'Supprimer le volume';

  @override
  String get maintenanceResourceFilter => 'Filtrer par nom ou ID';

  @override
  String get maintenanceResourceReferences => 'Références de conteneurs';

  @override
  String get maintenanceVolumeDriver => 'Pilote du volume';

  @override
  String get maintenanceImageTag => 'Étiquette';

  @override
  String get maintenanceImageQuery => 'Mot-clé de l’image';

  @override
  String get maintenanceImageSearch => 'Rechercher des images';

  @override
  String get maintenanceImageSearchHelp =>
      'Rechercher Docker Hub via le proxy système global (50 résultats maximum), avec statistiques, icônes et tags. Saisissez les images privées sous la forme registre/image:tag.';

  @override
  String get maintenanceImageStars => 'Étoiles';

  @override
  String get maintenanceImageOfficial => 'Officielle';

  @override
  String get maintenanceImageReference => 'Référence de l’image';

  @override
  String get maintenanceImagePullHelp =>
      'Les images sont téléchargées et vérifiées via le proxy système global, puis importées directement sur cette machine ou transférées vers une machine distante. Le moteur et les identifiants de registre sélectionnés sont utilisés. Augmentez le délai pour les grandes images.';

  @override
  String get maintenanceContainerNameOptional =>
      'Nom du conteneur (facultatif)';

  @override
  String get maintenanceContainerStartAfterCreate =>
      'Démarrer après la création';

  @override
  String get maintenanceHostAddress => 'Adresse de l’hôte';

  @override
  String get maintenanceHostPort => 'Port hôte';

  @override
  String get maintenanceContainerPort => 'Port du conteneur';

  @override
  String get maintenanceBindMount => 'Dossier de l’hôte';

  @override
  String get maintenanceReadOnlyMount => 'Lecture seule';

  @override
  String get maintenanceResourceAddRow => 'Ajouter une entrée';

  @override
  String get maintenanceContainerMounts => 'Montages';

  @override
  String get maintenanceMountSource => 'Nom du volume ou chemin hôte';

  @override
  String get maintenanceMountTarget => 'Chemin dans le conteneur';

  @override
  String get maintenanceResourceAdvanced => 'Configuration avancée';

  @override
  String get maintenanceCpuLimit => 'Limite CPU (cœurs)';

  @override
  String get maintenanceMemoryLimit => 'Limite de mémoire';

  @override
  String get maintenanceContainerCommandArguments => 'Commande et arguments';

  @override
  String get maintenanceArgumentsOnePerLine =>
      'Un argument par ligne ; laisser vide pour les valeurs de l’image.';

  @override
  String get maintenanceVolumeOptions => 'Options du pilote';

  @override
  String get maintenanceResourceUncertain =>
      'La fin de l’opération n’a pas pu être confirmée. Actualiser l’état cible avant de réessayer.';

  @override
  String get maintenanceResourceSuccess => 'Opération terminée';

  @override
  String get maintenanceResourceCloseRefresh => 'Fermer et actualiser';

  @override
  String get maintenanceResourceUnsupported =>
      'Ce moteur ne fournit pas cette interface. Sélectionner Docker, Podman ou nerdctl pour gérer les images et volumes locaux.';

  @override
  String get maintenanceResourceValidation => 'Vérifier la configuration';

  @override
  String get maintenanceImageRemoveHelp =>
      'Supprimer cette image locale sans forcer. Le moteur peut refuser si des conteneurs la référencent.';

  @override
  String get maintenanceVolumeRemoveHelp =>
      'Supprimer définitivement ce volume et ses données. Les volumes utilisés ne sont pas supprimés de force.';

  @override
  String get maintenanceResourceParameters => 'Paramètres';

  @override
  String get maintenanceRestartUnlessStopped => 'Redémarrer sauf arrêt manuel';

  @override
  String get maintenancePortAutomatic => 'Vide : attribution automatique';

  @override
  String get maintenanceOperationTimeout => 'Délai de l’opération';

  @override
  String get maintenanceImageDownloads => 'Téléchargements';

  @override
  String get maintenanceImagePullOnly => 'Télécharger uniquement';

  @override
  String get maintenanceImageSelectTag => 'Choisir une étiquette';

  @override
  String get maintenanceImageMetadataUnavailable =>
      'Certaines informations publiques sont indisponibles. Les compteurs manquants affichent — ; le choix de version et le téléchargement restent disponibles.';

  @override
  String get maintenanceImageTagHelp =>
      'Choisissez une version ou saisissez une étiquette. Lancez une recherche pour filtrer les versions.';

  @override
  String get maintenanceImageTagsUnavailable =>
      'Étiquettes indisponibles. Saisissez celle souhaitée manuellement.';

  @override
  String get maintenanceImageTagInvalid =>
      'Utilisez 1 à 128 lettres, chiffres, tirets bas, points ou tirets. Ne commencez pas par un point ou un tiret.';

  @override
  String get maintenanceImageTagRetry => 'Recharger';

  @override
  String get maintenanceImageTagsMore => 'Charger plus d’étiquettes';

  @override
  String get maintenanceImageTagSearch => 'Rechercher des étiquettes';

  @override
  String maintenanceImageResults(int count) {
    return 'Résultats · $count';
  }

  @override
  String get maintenanceTelemetryRuntimeOverview => 'Vue du moteur';

  @override
  String get maintenanceTelemetryApiHealth => 'État du service API';

  @override
  String get maintenanceTelemetryNodeMetrics => 'Utilisation des nœuds';

  @override
  String get maintenanceTelemetryWorkloads => 'Charges de travail';

  @override
  String get maintenanceTelemetryServiceNetwork => 'Services et réseau';

  @override
  String get maintenanceTelemetryPersistentStorage => 'Stockage persistant';

  @override
  String get maintenanceTelemetryStorageClaims => 'Demandes de stockage';

  @override
  String get maintenanceTelemetryQuotas => 'Quotas de ressources';

  @override
  String get maintenanceTelemetryWarningEvents => 'Événements d’alerte';

  @override
  String get maintenanceTelemetryDiskUsage =>
      'Utilisation et espace récupérable';

  @override
  String get maintenanceTelemetrySampleTime => 'Heure du relevé';

  @override
  String get maintenanceTelemetryPending => 'En attente du relevé';

  @override
  String get maintenanceTelemetryConnecting => 'Connexion en cours';

  @override
  String get maintenanceTelemetryFullMetadata => 'Métadonnées complètes';

  @override
  String get maintenanceTelemetryCpuCapacity => 'Capacité CPU';

  @override
  String get maintenanceTelemetryCpuAllocatable => 'CPU allouable';

  @override
  String get maintenanceTelemetryMemoryCapacity => 'Capacité mémoire';

  @override
  String get maintenanceTelemetryMemoryAllocatable => 'Mémoire allouable';

  @override
  String get maintenanceTelemetryPodCapacity => 'Capacité des pods';

  @override
  String get maintenanceTelemetryDesiredReplicas => 'Réplicas souhaités';

  @override
  String get maintenanceTelemetryReadyReplicas => 'Réplicas prêts';

  @override
  String get maintenanceTelemetryAvailableReplicas => 'Réplicas disponibles';

  @override
  String get maintenanceTelemetryDesiredNodes => 'Nœuds souhaités';

  @override
  String get maintenanceTelemetryReadyNodes => 'Nœuds prêts';

  @override
  String get maintenanceTelemetrySucceeded => 'Réussites';

  @override
  String get maintenanceTelemetryFailed => 'Échecs';

  @override
  String get maintenanceTelemetryNetworkRules => 'Règles réseau';

  @override
  String get maintenanceTelemetryStorageClass => 'Classe de stockage';

  @override
  String get maintenanceTelemetryResourceRequests => 'Ressources demandées';

  @override
  String get maintenanceTelemetryAccessModes => 'Modes d’accès';

  @override
  String get maintenanceTelemetryReclaimPolicy => 'Politique de récupération';

  @override
  String get maintenanceTelemetryResourceUsed => 'Ressources utilisées';

  @override
  String get maintenanceTelemetryStorageRoot => 'Répertoire de stockage';

  @override
  String get maintenanceTelemetryExternalAddress => 'Adresse externe';

  @override
  String get maintenanceTelemetryVolumeBinding => 'Mode de liaison du volume';

  @override
  String get maintenanceTelemetryVolumeExpansion => 'Extension autorisée';

  @override
  String get maintenanceTelemetryMemoryPercent => 'Mémoire utilisée (%)';

  @override
  String get maintenanceTelemetryNotReady => 'Non prêt';

  @override
  String get maintenanceTelemetryMetricsUnavailable =>
      'Les métriques sont indisponibles. Vérifiez le metrics-server du cluster et les droits d’accès.';

  @override
  String get maintenanceTelemetryKubernetesOverview => 'Vue Kubernetes';

  @override
  String get maintenanceTelemetryRuntimeHelp =>
      'Consultez l’état du moteur, les ressources et les métadonnées.';

  @override
  String get maintenanceTelemetryKubernetesHelp =>
      'Consultez l’état du cluster, les nœuds, les charges et les métriques.';

  @override
  String maintenanceTelemetryCompleted(int completed, int total) {
    return 'Contrôles terminés : $completed/$total';
  }

  @override
  String get maintenanceTelemetryPartial =>
      'Certaines données sont indisponibles';

  @override
  String get maintenanceTelemetryCancelled => 'Collecte annulée';

  @override
  String maintenanceLoadWindow(String minutes) {
    return '$minutes min';
  }

  @override
  String get maintenanceTaskSchedulerCron => 'Tâches Cron';

  @override
  String get maintenanceTaskSchedulerSystemd => 'Minuteries systemd';

  @override
  String get maintenanceTaskSchedulerLaunchd => 'Tâches launchd';

  @override
  String get maintenanceTaskNoMatches =>
      'Aucune tâche correspondante. Modifiez la recherche ou le filtre.';

  @override
  String get maintenanceTaskExecutablePaths =>
      'Chemins de recherche des exécutables';

  @override
  String get maintenanceTaskMailTo => 'Destinataire des notifications';

  @override
  String get maintenanceTaskMailFrom => 'Expéditeur des notifications';

  @override
  String get maintenanceTaskOverview => 'Aperçu de la tâche';

  @override
  String get maintenanceTaskExecution => 'Configuration d’exécution';

  @override
  String get maintenanceTaskHistory => 'Historique d’exécution';

  @override
  String get maintenanceTaskHistoryUnavailable =>
      'Le planificateur ne fournit ni horaires ni résultats d’exécution';

  @override
  String maintenanceTaskEvery(String duration) {
    return 'Toutes les $duration';
  }

  @override
  String get maintenanceTaskIntervalLabel => 'Intervalle d’exécution';

  @override
  String get maintenanceCronEvery => 'Chaque valeur';

  @override
  String get maintenanceCronSelect => 'Choisir les valeurs';

  @override
  String get maintenanceCronStep => 'Intervalle fixe';

  @override
  String get maintenanceCronPreserve => 'Conserver la règle actuelle';

  @override
  String get maintenanceCronMinute => 'Chaque minute';

  @override
  String get maintenanceCronHourly => 'Toutes les heures';

  @override
  String get maintenanceCronDaily => 'Chaque jour';

  @override
  String get maintenanceCronWeekly => 'Chaque semaine';

  @override
  String get maintenanceCronMonthly => 'Chaque mois';

  @override
  String get maintenanceCronReboot => 'Au démarrage du système';

  @override
  String get maintenanceCronHelp =>
      'Utilise le fuseau horaire des tâches de la machine cible. Si la date et le jour de semaine sont limités, un seul critère suffit.';

  @override
  String get maintenanceCronCommandHelp =>
      'Crontab exige une commande shell sur une ligne. Séparez les commandes par des points-virgules ou appelez un fichier script.';

  @override
  String get maintenanceImageDownloading => 'Téléchargement de l’image';

  @override
  String get maintenanceImageUploading => 'Transfert vers la machine cible';

  @override
  String get maintenanceImageImporting => 'Importation de l’image';

  @override
  String get maintenanceImageAuthFailed =>
      'Échec de l’authentification au registre. Vérifiez les identifiants de connexion sur la machine cible.';

  @override
  String get maintenanceImagePlatformUnavailable =>
      'Aucune version de l’image ne correspond au système et à l’architecture de l’environnement cible.';

  @override
  String get maintenanceCronDate => 'Jour';

  @override
  String get maintenanceCronMonth => 'Mois';

  @override
  String get maintenanceCronAny => 'Tous';

  @override
  String maintenanceCronStepValue(String count) {
    return 'Intervalle $count';
  }

  @override
  String get maintenanceTaskEnabledHelp =>
      'Exécuter selon le planning lorsque la tâche est activée.';

  @override
  String get maintenanceTaskDisabledHelp =>
      'Conserver la configuration et suspendre l’exécution.';

  @override
  String codeEditorCursorPosition(int line, int column) {
    return 'Ligne $line, colonne $column';
  }

  @override
  String get codeEditorShellLanguage => 'Script shell / Bash';

  @override
  String get codeEditorPlainText => 'Texte brut';

  @override
  String get codeEditorUndo => 'Annuler';

  @override
  String get codeEditorRedo => 'Rétablir';

  @override
  String get codeEditorFind => 'Rechercher';

  @override
  String get codeEditorImport => 'Importer un fichier de code';

  @override
  String get codeEditorImporting => 'Importation en cours';

  @override
  String get codeEditorWordWrapEnable => 'Activer le retour à la ligne';

  @override
  String get codeEditorWordWrapDisable => 'Désactiver le retour à la ligne';

  @override
  String codeEditorFileType(String language) {
    return 'Fichiers de code $language';
  }

  @override
  String get codeEditorFormatDone => 'Code mis en forme.';

  @override
  String get codeEditorFormatUnchanged => 'Le contenu est déjà mis en forme.';

  @override
  String get codeEditorJsonInvalid =>
      'Syntaxe JSON invalide ; mise en forme impossible.';

  @override
  String codeEditorImportSuccess(String file) {
    return 'Fichier de code importé : $file';
  }

  @override
  String get codeEditorImportTooLarge =>
      'Les fichiers de code ne doivent pas dépasser 512 Kio.';

  @override
  String get codeEditorImportInvalid =>
      'Le fichier de code n’est pas un texte UTF-8 valide.';

  @override
  String get codeEditorImportFailed =>
      'Impossible de lire le fichier de code. Vérifiez son accessibilité.';

  @override
  String get maintenanceImageRepositoryDetails => 'Aperçu du dépôt';

  @override
  String get maintenanceImageNamespace => 'Espace de noms';

  @override
  String get maintenanceImageLastUpdated => 'Dernière mise à jour';

  @override
  String get maintenanceImageTagDetails => 'Tag et plateformes';

  @override
  String get maintenanceImageLastPushed => 'Dernière publication';

  @override
  String get maintenanceImageVariant => 'Variante d’architecture';

  @override
  String get maintenanceImageFullDescription => 'Description complète';

  @override
  String get maintenanceImageRepositoryUnsupported =>
      'Les détails publics ne sont pas disponibles pour ce registre. Vous pouvez toujours choisir un tag et télécharger l’image.';

  @override
  String get maintenanceImageRepositoryUnavailable =>
      'Les détails du dépôt sont temporairement indisponibles. Les informations de recherche sont conservées ; veuillez réessayer.';

  @override
  String get maintenanceImageTagDetailsUnavailable =>
      'Les détails de ce tag sont temporairement indisponibles. Réessayez ou choisissez un autre tag.';

  @override
  String maintenanceImageTagNotFound(String tag) {
    return 'Le tag « $tag » n’existe pas. Sélectionnez un autre tag.';
  }

  @override
  String get maintenanceImageNoTags =>
      'Ce dépôt n’a aucun tag disponible. Actualisez ou sélectionnez une autre image.';

  @override
  String maintenanceImageDefaultTagChanged(String tag) {
    return 'Ce dépôt n’a pas de tag latest. Le tag disponible « $tag » a été sélectionné.';
  }

  @override
  String get maintenanceImagePlatforms => 'Plateformes';

  @override
  String get maintenanceImagePublisherContent =>
      'Documentation originale fournie par l’auteur du dépôt.';

  @override
  String maintenanceImageArchitectureBits(int bits) {
    return '$bits bits';
  }

  @override
  String get maintenanceImagePlatformSearch =>
      'Rechercher un système, une architecture ou une empreinte';

  @override
  String maintenanceImagePlatformCount(int count) {
    return 'Plateformes disponibles · $count';
  }

  @override
  String get maintenanceImageDetailsTitle => 'Détails de l’image';

  @override
  String get maintenanceImagePlatformsMore => 'Charger plus de plateformes';

  @override
  String get maintenanceImageRepositoryType => 'Type de dépôt';

  @override
  String get maintenanceImageStatusDescription => 'Description de l’état';

  @override
  String get maintenanceImagePrivate => 'Dépôt privé';

  @override
  String get maintenanceImageAutomated => 'Builds automatisés';

  @override
  String get maintenanceImageLastModified => 'Dernière modification';

  @override
  String get maintenanceImageRegistered => 'Date d’enregistrement';

  @override
  String get maintenanceImageCollaborators => 'Nombre de collaborateurs';

  @override
  String get maintenanceImageAffiliation => 'Affiliation du dépôt';

  @override
  String get maintenanceImageHubUser => 'Utilisateur Docker Hub';

  @override
  String get maintenanceImageStarred => 'Ajouté aux favoris';

  @override
  String get maintenanceImageMediaType => 'Type de média';

  @override
  String get maintenanceImageContentType => 'Type de contenu';

  @override
  String get maintenanceImageCategories => 'Catégories';

  @override
  String get maintenanceImageImmutableTags => 'Immutabilité des tags';

  @override
  String get maintenanceImageTagRules => 'Règles';

  @override
  String get maintenanceImageStorageSize => 'Stockage utilisé';

  @override
  String get maintenanceImageCreator => 'Identifiant du créateur';

  @override
  String get maintenanceImageLastUpdater => 'Identifiant du dernier auteur';

  @override
  String get maintenanceImageLastUpdaterName => 'Dernier auteur';

  @override
  String get maintenanceImageRegistryV2 => 'Protocole de registre V2';

  @override
  String get maintenanceImageTagStatus => 'État du tag';

  @override
  String get maintenanceImageLastPulled => 'Dernière récupération';

  @override
  String get maintenanceImageFeatures => 'Fonctionnalités de la plateforme';

  @override
  String get maintenanceImageOsFeatures => 'Fonctionnalités du système';

  @override
  String get maintenanceImageAdminPermission => 'Droit d’administration';

  @override
  String get maintenanceImageReadPermission => 'Droit de lecture';

  @override
  String get maintenanceImageWritePermission => 'Droit d’écriture';

  @override
  String get maintenanceImageSlug => 'Identifiant court';

  @override
  String get maintenanceImagePreparing =>
      'Préparation du téléchargement de l’image';

  @override
  String get resourcePreparing => 'Préparation des ressources';

  @override
  String get resourceDownloading => 'Téléchargement des ressources';

  @override
  String resourceDownloadFiles(int completed, int total) {
    return '$completed / $total fichiers';
  }

  @override
  String get maintenanceResourceSharedSize => 'Taille partagée';

  @override
  String get maintenanceResourceUniqueSize => 'Taille exclusive';

  @override
  String get maintenanceResourceWritableSize =>
      'Taille de la couche modifiable';

  @override
  String get maintenanceResourceRootSize => 'Taille du système de fichiers';

  @override
  String get maintenanceResourceScope => 'Portée';

  @override
  String get maintenanceResourceLayerCount => 'Couches';

  @override
  String get maintenanceContainerUnhealthy => 'Défaillant';

  @override
  String get maintenanceKubernetesContextMissing =>
      'Le contexte Kubernetes courant n’est pas configuré';

  @override
  String get maintenanceKubernetesContextMissingHelp =>
      'Configurez kubeconfig sur la machine cible, sélectionnez le contexte avec kubectl config use-context <nom-du-contexte>, puis actualisez.';

  @override
  String get maintenanceKubernetesContextMissingStatus =>
      'Contexte non configuré';

  @override
  String maintenanceRuntimeCapability(String name) {
    return 'Prise en charge : $name';
  }

  @override
  String maintenanceRuntimeComponentBuild(String component) {
    return 'Version de $component';
  }

  @override
  String get maintenanceRuntimeCpuSet => 'Affinité CPU';

  @override
  String get maintenanceRuntimeDebug => 'Mode débogage';

  @override
  String get maintenanceRuntimeIpv4Forwarding => 'Transfert IPv4';

  @override
  String get maintenanceRuntimeOomKillDisable => 'Désactiver l’arrêt OOM';

  @override
  String get maintenanceRuntimeEventListeners =>
      'Nombre d’écouteurs d’événements';

  @override
  String get maintenanceRuntimeExperimental => 'Fonctionnalités expérimentales';

  @override
  String get maintenanceRuntimeSwarm => 'Cluster Swarm';

  @override
  String get maintenanceRuntimeNodeId => 'Identifiant du nœud';

  @override
  String get maintenanceRuntimeNodeAddress => 'Adresse du nœud';

  @override
  String get maintenanceRuntimeNodeState => 'État du nœud local';

  @override
  String get maintenanceRuntimeManagerNode => 'Nœud gestionnaire';

  @override
  String get maintenanceRuntimeRemoteManagers => 'Nœuds gestionnaires distants';

  @override
  String get maintenanceRuntimeFirewallBackend => 'Moteur du pare-feu';

  @override
  String get maintenanceRuntimeFirewallDriver => 'Pilote du pare-feu';

  @override
  String get maintenanceRuntimeDiscoveredDevices => 'Périphériques détectés';

  @override
  String get maintenanceRuntimeContainerd => 'Service Containerd';

  @override
  String get maintenanceRuntimeNamespaces => 'Espaces de noms';

  @override
  String get maintenanceRuntimeContainerNamespace =>
      'Espace de noms des conteneurs';

  @override
  String get maintenanceRuntimePluginNamespace =>
      'Espace de noms des extensions';

  @override
  String get maintenanceRuntimeClientInfo => 'Informations du client';

  @override
  String get maintenanceRuntimeClient => 'Client';

  @override
  String get maintenanceRuntimeServer => 'Serveur';

  @override
  String get maintenanceRuntimeComponents => 'Composants';

  @override
  String get maintenanceRuntimeDetails => 'Détails';

  @override
  String get maintenanceRuntimeDefaultApiVersion => 'Version API par défaut';

  @override
  String get maintenanceRuntimeMinApiVersion => 'Version API minimale';

  @override
  String get maintenanceRuntimeSchemaVersion => 'Version du schéma';

  @override
  String get maintenanceRuntimeBuildTime => 'Date de compilation';

  @override
  String get maintenanceRuntimeModule => 'Module';

  @override
  String get maintenanceRuntimeModuleVersion => 'Version du module';

  @override
  String get maintenanceRuntimeCdiDirectories =>
      'Dossiers de configuration CDI';

  @override
  String get maintenanceRuntimeNri => 'Interface de ressources du nœud (NRI)';

  @override
  String get maintenanceRuntimeRegistryAddress =>
      'Adresse de l’index du registre';

  @override
  String get maintenanceRuntimeHttpProxy => 'Proxy HTTP';

  @override
  String get maintenanceRuntimeHttpsProxy => 'Proxy HTTPS';

  @override
  String get maintenanceRuntimeIsolation => 'Isolation des conteneurs';

  @override
  String get maintenanceRuntimeInitBinary => 'Programme d’initialisation';

  @override
  String get maintenanceRuntimeLicense => 'Licence du produit';

  @override
  String get maintenanceRuntimeAddressPools => 'Pools d’adresses par défaut';

  @override
  String get maintenanceRuntimeSubnetPrefix =>
      'Longueur du préfixe de sous-réseau';

  @override
  String get maintenanceRuntimeGenericResources => 'Ressources génériques';

  @override
  String get maintenanceRuntimeSystemStatus => 'État du système';

  @override
  String get maintenanceRuntimeVolumePlugins => 'Extensions de volumes';

  @override
  String get maintenanceRuntimeNetworkPlugins => 'Extensions réseau';

  @override
  String get maintenanceRuntimeLogPlugins => 'Extensions de journalisation';

  @override
  String get maintenanceRuntimeAuthorizationPlugins =>
      'Extensions d’autorisation';

  @override
  String get maintenanceRuntimeInsecureRegistries =>
      'Sous-réseaux de registres non sécurisés';

  @override
  String get maintenanceRuntimeRegistryIndexes =>
      'Configuration des index de registres';

  @override
  String get maintenanceRuntimeRegistryMirrors => 'Miroirs de registres';

  @override
  String get maintenanceRuntimeSecureRegistry =>
      'Connexion sécurisée au registre';

  @override
  String get maintenanceRuntimeOfficialRegistry => 'Registre officiel';

  @override
  String get maintenanceRuntimeNodes => 'Nombre de nœuds';

  @override
  String get maintenanceRuntimeManagers => 'Nombre de gestionnaires';

  @override
  String get maintenanceRuntimeCluster => 'Informations du cluster';

  @override
  String get maintenanceRuntimeTlsInfo => 'Informations du certificat TLS';

  @override
  String get maintenanceRuntimeTrustRoot => 'Certificat racine';

  @override
  String get maintenanceRuntimeCertSubject => 'Émetteur du certificat';

  @override
  String get maintenanceRuntimeCertPublicKey => 'Clé publique de l’émetteur';

  @override
  String get maintenanceRuntimeRootRotation => 'Rotation du certificat racine';

  @override
  String get maintenanceRuntimeDataPathPort => 'Port du canal de données';

  @override
  String get maintenanceRuntimeNodeLocked => 'Verrouillé';

  @override
  String get maintenanceRuntimeHost => 'Informations de l’hôte';

  @override
  String get maintenanceRuntimeStore => 'Informations du stockage';

  @override
  String maintenanceRuntimeComponentInfo(String component) {
    return 'Informations de $component';
  }

  @override
  String maintenanceRuntimeSecurityFeature(String name) {
    return 'Protection $name';
  }

  @override
  String get maintenanceRuntimeDistribution => 'Distribution du système';

  @override
  String get maintenanceRuntimeNetworkBackend => 'Moteur réseau';

  @override
  String get maintenanceRuntimeNetworkBackendInfo =>
      'Informations du moteur réseau';

  @override
  String get maintenanceRuntimeDatabaseBackend => 'Moteur de base de données';

  @override
  String get maintenanceRuntimeEventLogger => 'Journal des événements';

  @override
  String get maintenanceRuntimeFreeLocks => 'Verrous disponibles';

  @override
  String get maintenanceRuntimeIdMappings =>
      'Correspondances des utilisateurs et groupes';

  @override
  String get maintenanceRuntimeUidMappings =>
      'Correspondances des ID utilisateur';

  @override
  String get maintenanceRuntimeGidMappings =>
      'Correspondances des ID de groupe';

  @override
  String get maintenanceRuntimeOciRuntime => 'Environnement OCI';

  @override
  String get maintenanceRuntimeRemoteSocket => 'Point de connexion du service';

  @override
  String get maintenanceRuntimeRootlessNetwork =>
      'Programme réseau sans privilèges';

  @override
  String get maintenanceRuntimeRootlessPortForwarder =>
      'Transfert de ports sans privilèges';

  @override
  String get maintenanceRuntimeRemoteService => 'Service distant';

  @override
  String get maintenanceRuntimeRootless => 'Mode sans privilèges';

  @override
  String get maintenanceRuntimeSeccompProfile => 'Profil Seccomp';

  @override
  String get maintenanceRuntimeGraphOptions => 'Options du pilote de stockage';

  @override
  String get maintenanceRuntimeStorageAllocated =>
      'Capacité du dossier de stockage';

  @override
  String get maintenanceRuntimeStorageUsed =>
      'Utilisation du dossier de stockage';

  @override
  String get maintenanceRuntimeImageCopyTemp =>
      'Dossier temporaire de copie des images';

  @override
  String get maintenanceRuntimeContainerStore =>
      'Statistiques du stockage des conteneurs';

  @override
  String get maintenanceRuntimeImageStore =>
      'Statistiques du stockage des images';

  @override
  String get maintenanceRuntimeRunRoot => 'Dossier des données d’exécution';

  @override
  String get maintenanceRuntimeVolumePath => 'Dossier des volumes';

  @override
  String get maintenanceRuntimeTransientStore => 'Stockage temporaire';

  @override
  String get maintenanceRuntimeEmulatedArchitectures => 'Architectures émulées';

  @override
  String get maintenanceRuntimePackage => 'Paquet logiciel';

  @override
  String get maintenanceRuntimeCodename => 'Nom de code de la distribution';

  @override
  String get maintenanceRuntimeLinkMode => 'Mode de liaison';

  @override
  String get maintenanceRuntimeCpuUser => 'Utilisation CPU en mode utilisateur';

  @override
  String get maintenanceRuntimeCpuSystem => 'Utilisation CPU en mode système';

  @override
  String get maintenanceRuntimeCpuIdle => 'Pourcentage CPU inactif';

  @override
  String get maintenanceRuntimeExists => 'Point de connexion existant';

  @override
  String get maintenanceRuntimeMappedContainerId => 'ID initial du conteneur';

  @override
  String get maintenanceRuntimeMappedHostId => 'ID initial de l’hôte';

  @override
  String get maintenanceRuntimeMappedIdCount => 'Nombre d’ID mappés';

  @override
  String get maintenanceRuntimeExpectedBuild => 'Build attendu';

  @override
  String get messageToolNameTask => 'Déléguer une tâche';

  @override
  String get messageToolNameBash => 'Exécuter une commande';

  @override
  String get messageToolNameBashBackground => 'Commande en arrière-plan';

  @override
  String get messageToolNameTaskOutput => 'Résultat de tâche';

  @override
  String get messageToolNameTaskStop => 'Arrêter la tâche';

  @override
  String get messageToolNameGlob => 'Rechercher des fichiers';

  @override
  String get messageToolNameGrep => 'Rechercher du contenu';

  @override
  String get messageToolNameLs => 'Parcourir le dossier';

  @override
  String get messageToolNameExitPlanMode => 'Soumettre le plan';

  @override
  String get messageToolNameEndVoiceConversation =>
      'Terminer la conversation vocale';

  @override
  String get messageToolNameRead => 'Lire le fichier';

  @override
  String get messageToolNameEdit => 'Modifier le fichier';

  @override
  String get messageToolNameMultiEdit => 'Modification groupée';

  @override
  String get messageToolNameApplyFileDiffs => 'Appliquer les correctifs';

  @override
  String get messageToolNameWrite => 'Écrire le fichier';

  @override
  String get messageToolNameNotebookEdit => 'Modifier le notebook';

  @override
  String get messageToolNameWebFetch => 'Lire la page web';

  @override
  String get messageToolNameTodoWrite => 'Mettre à jour les tâches';

  @override
  String get messageToolNameWebSearch => 'Rechercher sur le web';

  @override
  String get messageToolNameLsp => 'Navigation dans le code';

  @override
  String get messageToolNameCodebaseSearch => 'Rechercher dans le code';

  @override
  String get messageToolNameGit => 'Gestion de versions';

  @override
  String get messageToolNameDeleteFile => 'Supprimer le fichier';

  @override
  String get messageToolNameReadLints => 'Lire les diagnostics';

  @override
  String get messageToolNameAskUserChoice => 'Demander un choix';

  @override
  String get messageToolNameSkillManager => 'Gérer les compétences';

  @override
  String get messageToolNameToolSearch => 'Rechercher des outils';

  @override
  String get messageToolNameMemory => 'Gérer la mémoire';

  @override
  String get messageToolNameKnowledgeSearch =>
      'Rechercher dans les connaissances';

  @override
  String get messageToolNameKnowledgeRead => 'Lire les connaissances';

  @override
  String get messageToolNameWorkflowList => 'Parcourir les workflows';

  @override
  String get messageToolNameWorkflowDetail => 'Voir le workflow';

  @override
  String get messageToolNameWorkflowExecute => 'Exécuter le workflow';

  @override
  String get messageToolNameWorkflowExecutionStatus => 'État du workflow';

  @override
  String get messageToolNameCronCreate => 'Créer une planification';

  @override
  String get messageToolNameCronEdit => 'Modifier la planification';

  @override
  String get messageToolNameCronDelete => 'Supprimer la planification';

  @override
  String get messageToolNameCronEnable => 'Activer la planification';

  @override
  String get messageToolNameCronDisable => 'Désactiver la planification';

  @override
  String get messageToolNameMachineTerminalRead => 'Lire le terminal';

  @override
  String get messageToolNameMachineTerminalWrite => 'Écrire dans le terminal';

  @override
  String get messageToolNameMachineTerminalExec => 'Exécuter dans le terminal';

  @override
  String get messageToolNameMachineTerminalControl => 'Contrôler le terminal';

  @override
  String get messageToolNameDingTalkToolSearch =>
      'Rechercher les outils DingTalk';

  @override
  String get messageToolNameDingtalkDws => 'Espace DingTalk';

  @override
  String get messageToolNameDingtalkImageGeneration => 'Générer une image';

  @override
  String get messageToolNameDingtalkVideoGeneration => 'Générer une vidéo';

  @override
  String get messageToolNameDingtalkAudioGeneration => 'Générer un audio';

  @override
  String get messageToolNameDownloadFile => 'Télécharger le fichier';

  @override
  String get messageLoadFullContent => 'Charger le contenu complet';

  @override
  String get messageLoadingContent => 'Chargement';

  @override
  String get messageCacheHit => 'Cache utilisé';

  @override
  String get messageFetchCacheHit => 'Cache de récupération utilisé';

  @override
  String get messageCache => 'Cache';

  @override
  String get messageFetchCache => 'Cache de récupération';

  @override
  String get messageCacheStored => 'Mis en cache';

  @override
  String get messageCacheDisabled => 'Cache désactivé';

  @override
  String get messageCachedAt => 'Mis en cache à';

  @override
  String get messageExpiresAt => 'Expire à';

  @override
  String get messageSandboxBlocked => 'Bloqué par le bac à sable';

  @override
  String get messageSandboxProxy => 'Proxy du bac à sable';

  @override
  String get messageReasoning => 'Réflexion';

  @override
  String get fileMutationOpenDiffDialog => 'Ouvrir les différences';

  @override
  String fileMutationUnchangedLines(int count) {
    return '$count lignes inchangées';
  }

  @override
  String fileMutationCollapseUnchangedLines(int count) {
    return 'Replier $count lignes inchangées';
  }

  @override
  String get fileMutationExpandUnchanged => 'Développer le contenu inchangé';

  @override
  String get fileMutationCollapseUnchanged => 'Replier le contenu inchangé';

  @override
  String get fileMutationCollapseDiff => 'Replier les différences';

  @override
  String fileMutationExpandRemainingDiff(int count) {
    return 'Voir toutes les différences ($count lignes de plus)';
  }

  @override
  String get fileMutationRevealFile =>
      'Afficher dans le gestionnaire de fichiers';

  @override
  String get fileMutationRevealFileFailed =>
      'Impossible d’afficher ce chemin dans le gestionnaire de fichiers.';

  @override
  String get fileMutationJumpedBeforeCompression =>
      'Le message précède la compression. Le premier message visible est affiché.';

  @override
  String get fileMutationSourceMissing =>
      'Message source introuvable (il a peut-être été supprimé).';

  @override
  String fileMutationExportPickerFailed(String error) {
    return 'Export interrompu (sélecteur de fichiers indisponible) : $error';
  }

  @override
  String get fileMutationExportCancelled => 'Export annulé.';

  @override
  String fileMutationSaveFailed(String error) {
    return 'Échec de l’enregistrement : $error';
  }

  @override
  String fileMutationSavedTo(String path) {
    return 'Enregistré dans $path';
  }

  @override
  String get fileMutationRoundLoading =>
      'Récapitulatif des modifications en cours…';

  @override
  String get fileMutationRoundEmpty =>
      'Aucune modification de fichier dans ce tour.';

  @override
  String get fileMutationRoundTitle => 'Modifications de fichiers du tour';

  @override
  String get fileMutationLineStats => 'Lignes ajoutées et supprimées';

  @override
  String get fileMutationUndoRound =>
      'Annuler toutes les modifications du tour';

  @override
  String get fileMutationExportRound => 'Exporter le tour en JSON';

  @override
  String get fileMutationRefreshSummary => 'Actualiser le récapitulatif';

  @override
  String fileMutationRemainingRows(int count) {
    return 'Afficher $count lignes de plus';
  }

  @override
  String get fileMutationToggleDiff => 'Développer / replier les différences';

  @override
  String get fileMutationJumpToSource => 'Aller à l’appel d’outil source';

  @override
  String get fileMutationLoadingDiff => 'Chargement des différences…';

  @override
  String get fileMutationCreated => 'Créés';

  @override
  String get fileMutationModified => 'Modifiés';

  @override
  String get fileMutationDeleted => 'Supprimés';

  @override
  String get messageFullContentFailed =>
      'Impossible de charger le contenu complet. Réessayez.';

  @override
  String get messageStreaming => 'Génération en cours';

  @override
  String get messageReadAloud => 'Lire à voix haute';

  @override
  String get messageTranslating => 'Traduction en cours';

  @override
  String get messageOriginal => 'Voir l’original';

  @override
  String get messageLike => 'J’aime';

  @override
  String get messageImprove => 'À améliorer';

  @override
  String get messageDeleteFromHere => 'Supprimer à partir d’ici';

  @override
  String get messageAudit => 'Audit';

  @override
  String get messageShowRendered => 'Afficher le rendu';

  @override
  String get messageShowRaw => 'Afficher la source';

  @override
  String get messageOpenBrowser => 'Ouvrir dans le navigateur';

  @override
  String get messageAttachmentMissing =>
      'Pièce jointe introuvable ou déplacée.';

  @override
  String messageUnsafePath(String path) {
    return 'Chemin non sûr refusé : $path';
  }

  @override
  String messageOpenFileFailed(String error) {
    return 'Impossible d’ouvrir le fichier : $error';
  }

  @override
  String get messageCopyFile => 'Copier le fichier';

  @override
  String get messageCopying => 'Copie en cours…';

  @override
  String get messageCopyImage => 'Copier l’image';

  @override
  String get messageCopyImageUrlFallback =>
      'Impossible de copier l’image. Son adresse a été copiée.';

  @override
  String get messageImageLoadFailed => 'Impossible de charger l’image';

  @override
  String get messageMediaTimedOut =>
      'Chargement expiré. Ouvrez le média avec le lecteur système.';

  @override
  String get messageMediaInitFailed =>
      'Impossible d’initialiser l’aperçu. Ouvrez le média avec le lecteur système.';

  @override
  String get messageFullscreenPlayback => 'Lecture plein écran';

  @override
  String get messageMediaUrlCopied => 'Adresse du média copiée.';

  @override
  String get messageSystemPlayer => 'Lecteur système';

  @override
  String get messageGoalAutoFollowUp => 'Suivi automatique de l’objectif';

  @override
  String get messageGoalEvaluationRequest =>
      'Demande d’évaluation de l’objectif';

  @override
  String get messageGoalEvaluationResponse =>
      'Réponse d’évaluation de l’objectif';

  @override
  String get messageMachineExpertRequest => 'Demande à l’expert machine';

  @override
  String get messageTerminalBound =>
      'Le terminal cible est associé à cette tâche.';

  @override
  String get messageMachineExpert => 'Expert machine';

  @override
  String get messageTerminal => 'Terminal';

  @override
  String get messageLocation => 'Emplacement';

  @override
  String get messageRequest => 'Demande';

  @override
  String get messageWebEnvironmentBound =>
      'La page cible et l’environnement CDP sont associés à cette tâche.';

  @override
  String get messageWebReverse => 'Analyse Web';

  @override
  String get messageDeliverables => 'Livrables';

  @override
  String get messageAndroidEnvironmentBound =>
      'L’application cible et le périmètre d’analyse sont associés à cette tâche.';

  @override
  String get messageAndroidReverse => 'Analyse Android';

  @override
  String get messagePackage => 'Nom du paquet';

  @override
  String get messageApkPath => 'Chemin de l’APK';

  @override
  String get messageAnalysisMode => 'Mode d’analyse';

  @override
  String get messageAuthorizationScope => 'Périmètre autorisé';

  @override
  String get messageCardShortened =>
      'Le contenu est abrégé ; la source complète reste disponible pour l’audit et la copie.';

  @override
  String get messageContinueGoal => 'Poursuivre l’objectif actuel';

  @override
  String get messageVerifyGoal => 'Vérifier les preuves de l’objectif';

  @override
  String get messageGoalPassed => 'Preuves de l’objectif validées';

  @override
  String get messageGoalNeedsWork => 'Objectif encore à poursuivre';

  @override
  String get messageGoalFollowUpDescription =>
      'Le système a envoyé ce message pour poursuivre l’objectif après une évaluation insuffisante.';

  @override
  String get messageGoalEvaluatorDescription =>
      'L’évaluateur vérifie l’objectif actuel et la conversation récente pour confirmer son achèvement.';

  @override
  String get messageGoalEnoughEvidence =>
      'L’évaluateur a trouvé des preuves suffisantes pour valider l’objectif.';

  @override
  String get messageGoalInsufficientEvidence =>
      'L’évaluateur a jugé les preuves insuffisantes et demandé de poursuivre.';

  @override
  String get messageEvaluationSummary => 'Résumé de l’évaluation';

  @override
  String get messageNextStep => 'Étape suivante';

  @override
  String get messageTokens => 'jetons';

  @override
  String messageRecentCount(int count) {
    return '$count récents';
  }

  @override
  String get messageTotalTokens => 'Total des jetons';

  @override
  String get messageKnowledgeFailed => 'Échec de la base de connaissances';

  @override
  String get messageKnowledgeNoHits => 'Aucun résultat dans la base';

  @override
  String messageKnowledgeHits(int count) {
    return 'Base : $count résultats';
  }

  @override
  String messageKnowledgeHitsTokens(int count, int tokens) {
    return 'Base · $count résultats · $tokens jetons';
  }

  @override
  String messageKnowledgeSources(int count) {
    return '$count sources de la base';
  }

  @override
  String get messagePassed => 'Validé';

  @override
  String get messageAttachment => 'Pièce jointe';

  @override
  String messageSkillName(String name) {
    return 'Compétence · $name';
  }

  @override
  String get messageFullscreenInitFailed =>
      'Impossible d’initialiser la vidéo plein écran. Revenez et réessayez.';

  @override
  String get messageBackEsc => 'Retour (Échap)';

  @override
  String get messageAcceptance => 'Critères d’acceptation';

  @override
  String get messageAndroidReverseRequest => 'Demande d’analyse Android';

  @override
  String get messageCopyMedia => 'Copier le média';

  @override
  String get messageEvidenceRules => 'Règles de collecte des preuves';

  @override
  String get messageGoal => 'Objectif';

  @override
  String get messageOpenSystemApp => 'Ouvrir avec l’application système';

  @override
  String get messageOpenSystemPlayer => 'Ouvrir avec le lecteur système';

  @override
  String get messagePreciseTarget => 'Cible précise';

  @override
  String get messageSaveToDisk => 'Enregistrer sur le disque';

  @override
  String get messageWebReverseRequest => 'Demande d’analyse Web';

  @override
  String get messageExpandSummary => 'Développer le résumé';

  @override
  String get messageCollapseSummary => 'Replier le résumé';

  @override
  String get messageShowFullContent => 'Afficher le contenu complet';

  @override
  String get messageCollapseContent => 'Replier le contenu';

  @override
  String get messageImageMissing => 'Image introuvable ou déplacée.';

  @override
  String get messageGeneratingHtml => 'Génération de la carte HTML';

  @override
  String get messageCharacterUnit => ' caractères';

  @override
  String get messageRole => 'Rôle';

  @override
  String get messagePhase => 'Phase';

  @override
  String get messageRoleReader => 'Analyste';

  @override
  String get messageRolePlanner => 'Planificateur';

  @override
  String get messageRoleImplementer => 'Développeur';

  @override
  String get messageRoleReviewer => 'Évaluateur';

  @override
  String get messagePhaseMetaCollection => 'Collecte des métadonnées';

  @override
  String get messagePhaseReading => 'Analyse';

  @override
  String get messagePhasePlanning => 'Planification';

  @override
  String get messagePhaseImplementing => 'Mise en œuvre';

  @override
  String get messagePhaseReviewing => 'Vérification';

  @override
  String get messagePreviousResponse => 'Réponse précédente';

  @override
  String get messageNextResponse => 'Réponse suivante';

  @override
  String get messageFileCopied => 'Fichier copié dans le presse-papiers.';

  @override
  String get messageFilePathCopiedFallback =>
      'La copie de fichiers n’est pas disponible. Le chemin a été copié.';

  @override
  String get messageImageCopied => 'Image copiée dans le presse-papiers.';

  @override
  String get messageImageFileCopied =>
      'Fichier image copié dans le presse-papiers.';

  @override
  String get messageImagePathCopiedFallback =>
      'La copie d’images n’est pas disponible. Le chemin a été copié.';

  @override
  String get messageMediaFileCopied =>
      'Fichier média copié dans le presse-papiers.';

  @override
  String get messageMediaPathCopiedFallback =>
      'La copie de médias n’est pas disponible. Le chemin a été copié.';

  @override
  String messageCopyFailed(String error) {
    return 'Échec de la copie : $error';
  }

  @override
  String get messageSaving => 'Enregistrement…';

  @override
  String get messageSaveCancelled => 'Enregistrement annulé.';

  @override
  String messageSaveTimedOut(String error) {
    return 'Délai d’enregistrement dépassé : $error';
  }

  @override
  String get messageVideos => 'Vidéos';

  @override
  String get messageAudio => 'Audio';
}
