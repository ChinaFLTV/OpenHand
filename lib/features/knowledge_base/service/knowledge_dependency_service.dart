import '../../plugin_service/index.dart';

class KnowledgeDependencySnapshot {
  const KnowledgeDependencySnapshot({
    required this.docker,
    required this.qdrant,
    required this.ready,
    required this.messageZh,
    required this.messageEn,
  });

  final PluginInfo? docker;
  final PluginInfo? qdrant;
  final bool ready;
  final String messageZh;
  final String messageEn;

  bool get dockerInstalled => docker?.isInstalled == true;
  bool get qdrantInstalled => qdrant?.isInstalled == true;
  String get message => messageZh;

  String localizedMessage(bool isZh) => isZh ? messageZh : messageEn;
}

class KnowledgeDependencyService {
  const KnowledgeDependencyService();

  KnowledgeDependencySnapshot snapshot(PluginServiceController controller) {
    final docker = controller.pluginById('docker');
    final qdrant = controller.pluginById('qdrant');
    if (docker?.isInstalled != true) {
      final hasError = docker?.status == PluginStatus.error;
      final rawError = docker?.errorMessage?.trim();
      final messageZh = hasError
          ? (rawError?.isNotEmpty == true ? rawError! : 'Docker daemon 不可用。')
          : 'Docker 未安装。请在插件板块安装并启动 Docker。';
      final messageEn = hasError
          ? (rawError?.isNotEmpty == true
                ? rawError!
                : 'Docker daemon is unavailable.')
          : 'Docker is not installed. Install and start Docker in Plugins.';
      return KnowledgeDependencySnapshot(
        docker: docker,
        qdrant: qdrant,
        ready: false,
        messageZh: messageZh,
        messageEn: messageEn,
      );
    }
    if (qdrant?.isInstalled != true) {
      final hasError = qdrant?.status == PluginStatus.error;
      final rawError = qdrant?.errorMessage?.trim();
      final messageZh = hasError
          ? (rawError?.isNotEmpty == true ? rawError! : 'Qdrant 容器未运行。')
          : 'Qdrant 未安装。请在插件板块安装 Qdrant。';
      final messageEn = hasError
          ? (rawError?.isNotEmpty == true
                ? rawError!
                : 'Qdrant container is not running.')
          : 'Qdrant is not installed. Install Qdrant in Plugins.';
      return KnowledgeDependencySnapshot(
        docker: docker,
        qdrant: qdrant,
        ready: false,
        messageZh: messageZh,
        messageEn: messageEn,
      );
    }
    return KnowledgeDependencySnapshot(
      docker: docker,
      qdrant: qdrant,
      ready: true,
      messageZh: 'Docker 与 Qdrant 已就绪。',
      messageEn: 'Docker and Qdrant are ready.',
    );
  }
}
