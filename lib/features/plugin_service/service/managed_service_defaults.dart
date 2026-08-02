/// OpenHand 托管的基础服务默认参数。
///
/// 这些参数同时被插件扫描、生命周期操作和服务设置使用，避免三个界面
/// 各自维护连接地址、容器名和端口后出现状态不一致。
class ManagedServiceDefaults {
  const ManagedServiceDefaults._();

  static const String postgresqlContainerName = 'openhand-postgresql';
  static const String postgresqlImage = 'postgres:16-alpine';
  static const int postgresqlPort = 5432;
  static const String postgresqlEndpoint =
      'postgresql://openhand:openhand@127.0.0.1:5432/openhand';
  static const String postgresqlUser = 'openhand';
  static const String postgresqlPassword = 'openhand';
  static const String postgresqlDatabase = 'openhand';
  static const String postgresqlDataDestination = '/var/lib/postgresql/data';

  static const String redisContainerName = 'openhand-redis';
  static const String redisImage = 'redis:7-alpine';
  static const int redisPort = 6379;
  static const String redisEndpoint = 'redis://127.0.0.1:6379';
  static const String redisDataDestination = '/data';
}
