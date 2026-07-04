import '../../plugin_service/index.dart';

typedef AgentRuntimeAvailabilityProvider = AgentRuntimeAvailability Function();

class AgentRuntimeAvailability {
  const AgentRuntimeAvailability({
    required this.isLoading,
    required this.isInstalled,
    required this.isEnabled,
    required this.pluginName,
    this.version,
    this.installPath,
    this.errorMessage,
  });

  factory AgentRuntimeAvailability.fromHermesPlugin(
    PluginInfo? plugin, {
    required bool isLoading,
  }) {
    return AgentRuntimeAvailability(
      isLoading: isLoading,
      isInstalled: plugin?.isInstalled ?? false,
      isEnabled: plugin?.enabled ?? false,
      pluginName: plugin?.name ?? 'Hermes Agent',
      version: plugin?.installedVersion,
      installPath: plugin?.installPath,
      errorMessage: plugin?.errorMessage,
    );
  }

  static const AgentRuntimeAvailability optimistic = AgentRuntimeAvailability(
    isLoading: false,
    isInstalled: true,
    isEnabled: true,
    pluginName: 'Hermes Agent',
  );

  final bool isLoading;
  final bool isInstalled;
  final bool isEnabled;
  final String pluginName;
  final String? version;
  final String? installPath;
  final String? errorMessage;

  bool get canRun =>
      !isLoading &&
      isInstalled &&
      isEnabled &&
      (errorMessage == null || errorMessage!.trim().isEmpty);

  String get blockingReason {
    if (canRun) return '';
    if (isLoading) return '$pluginName runtime is still loading.';
    if (!isInstalled) return '$pluginName runtime is not installed.';
    if (!isEnabled) return '$pluginName runtime is disabled.';
    return errorMessage ?? '$pluginName runtime is unavailable.';
  }
}
