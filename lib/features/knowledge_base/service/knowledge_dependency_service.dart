import '../../plugin_service/index.dart';

class KnowledgeDependencySnapshot {
  const KnowledgeDependencySnapshot({
    required this.docker,
    required this.qdrant,
    required this.ready,
    required this.message,
  });

  final PluginInfo? docker;
  final PluginInfo? qdrant;
  final bool ready;
  final String message;

  bool get dockerInstalled => docker?.isInstalled == true;
  bool get qdrantInstalled => qdrant?.isInstalled == true;
}

class KnowledgeDependencyService {
  const KnowledgeDependencyService();

  KnowledgeDependencySnapshot snapshot(PluginServiceController controller) {
    final docker = controller.pluginById('docker');
    final qdrant = controller.pluginById('qdrant');
    if (docker?.isInstalled != true) {
      final message = docker?.status == PluginStatus.error
          ? docker?.errorMessage ?? 'Docker daemon 不可用。'
          : 'Docker 未安装。请在插件板块安装并启动 Docker。';
      return KnowledgeDependencySnapshot(
        docker: docker,
        qdrant: qdrant,
        ready: false,
        message: message,
      );
    }
    if (qdrant?.isInstalled != true) {
      final message = qdrant?.status == PluginStatus.error
          ? qdrant?.errorMessage ?? 'Qdrant 容器未运行。'
          : 'Qdrant 未安装。请在插件板块安装 Qdrant。';
      return KnowledgeDependencySnapshot(
        docker: docker,
        qdrant: qdrant,
        ready: false,
        message: message,
      );
    }
    return KnowledgeDependencySnapshot(
      docker: docker,
      qdrant: qdrant,
      ready: true,
      message: 'Docker 与 Qdrant 已就绪。',
    );
  }
}
