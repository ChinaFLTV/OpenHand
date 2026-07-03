import 'dart:ui';

import '../../../shared/util/localized_text.dart';
import '../../plugin_service/index.dart';

class KnowledgeDependencySnapshot {
  const KnowledgeDependencySnapshot({
    required this.docker,
    required this.qdrant,
    required this.ready,
    required this.messageZh,
    required this.messageZhHant,
    required this.messageEn,
    required this.messageFr,
    required this.messageDe,
    required this.messageJa,
  });

  final PluginInfo? docker;
  final PluginInfo? qdrant;
  final bool ready;
  final String messageZh;
  final String messageZhHant;
  final String messageEn;
  final String messageFr;
  final String messageDe;
  final String messageJa;

  bool get dockerInstalled => docker?.isInstalled == true;
  bool get qdrantInstalled => qdrant?.isInstalled == true;
  String get message => messageZh;

  String localizedMessage(Locale locale) {
    return openHandLocalizedTextForLocale(
      locale,
      zh: messageZh,
      zhHant: messageZhHant,
      en: messageEn,
      fr: messageFr,
      de: messageDe,
      ja: messageJa,
    );
  }
}

class KnowledgeDependencyService {
  const KnowledgeDependencyService();

  KnowledgeDependencySnapshot snapshot(PluginServiceController controller) {
    final docker = controller.pluginById('docker');
    final qdrant = controller.pluginById('qdrant');
    if (docker?.isInstalled != true) {
      final hasError = docker?.status == PluginStatus.error;
      final rawError = docker?.errorMessage?.trim();
      final message = _DependencyMessage(
        rawError: hasError ? rawError : null,
        zh: hasError ? 'Docker daemon 不可用。' : 'Docker 未安装。请在插件板块安装并启动 Docker。',
        zhHant: hasError
            ? 'Docker daemon 不可用。'
            : 'Docker 未安裝。請在外掛板塊安裝並啟動 Docker。',
        en: hasError
            ? 'Docker daemon is unavailable.'
            : 'Docker is not installed. Install and start Docker in Plugins.',
        fr: hasError
            ? 'Le daemon Docker est indisponible.'
            : 'Docker n’est pas installé. Installez et démarrez Docker dans Plugins.',
        de: hasError
            ? 'Der Docker-Daemon ist nicht verfügbar.'
            : 'Docker ist nicht installiert. Installieren und starten Sie Docker unter Plugins.',
        ja: hasError
            ? 'Docker daemon を利用できません。'
            : 'Docker がインストールされていません。プラグインで Docker をインストールして起動してください。',
      );
      return KnowledgeDependencySnapshot(
        docker: docker,
        qdrant: qdrant,
        ready: false,
        messageZh: message.zh,
        messageZhHant: message.zhHant,
        messageEn: message.en,
        messageFr: message.fr,
        messageDe: message.de,
        messageJa: message.ja,
      );
    }
    if (qdrant?.isInstalled != true) {
      final hasError = qdrant?.status == PluginStatus.error;
      final rawError = qdrant?.errorMessage?.trim();
      final message = _DependencyMessage(
        rawError: hasError ? rawError : null,
        zh: hasError ? 'Qdrant 容器未运行。' : 'Qdrant 未安装。请在插件板块安装 Qdrant。',
        zhHant: hasError ? 'Qdrant 容器未執行。' : 'Qdrant 未安裝。請在外掛板塊安裝 Qdrant。',
        en: hasError
            ? 'Qdrant container is not running.'
            : 'Qdrant is not installed. Install Qdrant in Plugins.',
        fr: hasError
            ? 'Le conteneur Qdrant n’est pas en cours d’exécution.'
            : 'Qdrant n’est pas installé. Installez Qdrant dans Plugins.',
        de: hasError
            ? 'Der Qdrant-Container läuft nicht.'
            : 'Qdrant ist nicht installiert. Installieren Sie Qdrant unter Plugins.',
        ja: hasError
            ? 'Qdrant コンテナが実行されていません。'
            : 'Qdrant がインストールされていません。プラグインで Qdrant をインストールしてください。',
      );
      return KnowledgeDependencySnapshot(
        docker: docker,
        qdrant: qdrant,
        ready: false,
        messageZh: message.zh,
        messageZhHant: message.zhHant,
        messageEn: message.en,
        messageFr: message.fr,
        messageDe: message.de,
        messageJa: message.ja,
      );
    }
    return KnowledgeDependencySnapshot(
      docker: docker,
      qdrant: qdrant,
      ready: true,
      messageZh: 'Docker 与 Qdrant 已就绪。',
      messageZhHant: 'Docker 與 Qdrant 已就緒。',
      messageEn: 'Docker and Qdrant are ready.',
      messageFr: 'Docker et Qdrant sont prêts.',
      messageDe: 'Docker und Qdrant sind bereit.',
      messageJa: 'Docker と Qdrant の準備ができています。',
    );
  }
}

class _DependencyMessage {
  _DependencyMessage({
    required String? rawError,
    required String zh,
    required String zhHant,
    required String en,
    required String fr,
    required String de,
    required String ja,
  }) : zh = _messageOrRaw(rawError, zh),
       zhHant = _messageOrRaw(rawError, zhHant),
       en = _messageOrRaw(rawError, en),
       fr = _messageOrRaw(rawError, fr),
       de = _messageOrRaw(rawError, de),
       ja = _messageOrRaw(rawError, ja);

  final String zh;
  final String zhHant;
  final String en;
  final String fr;
  final String de;
  final String ja;

  static String _messageOrRaw(String? rawError, String fallback) {
    final trimmed = rawError?.trim();
    return trimmed?.isNotEmpty == true ? trimmed! : fallback;
  }
}
