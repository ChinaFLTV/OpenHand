import '../../../app/support/openhand_paths.dart';
import '../../memory/model/user_memory_entry.dart';

class AiSessionRuntimeContext {
  const AiSessionRuntimeContext({
    required this.localeTag,
    required this.appVersion,
    required this.appBuildNumber,
    required this.settingsFilePath,
    required this.skillsStoragePath,
    required this.mcpServersFilePath,
    required this.userMemoryFilePath,
    required this.compressionThresholdChars,
    required this.memoryEnabled,
    required this.memoryEntries,
  });

  final String localeTag;
  final String appVersion;
  final String appBuildNumber;
  final String settingsFilePath;
  final String skillsStoragePath;
  final String mcpServersFilePath;
  final String userMemoryFilePath;
  final int compressionThresholdChars;
  final bool memoryEnabled;
  final List<UserMemoryEntry> memoryEntries;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'locale_tag': localeTag,
      'app_version': appVersion,
      'app_build_number': appBuildNumber,
      'application_directory': OpenHandPaths.applicationDirectoryPath(),
      'home_directory': OpenHandPaths.homeDirectoryPath(),
      'settings_file_path': settingsFilePath,
      'skills_storage_path': skillsStoragePath,
      'mcp_servers_file_path': mcpServersFilePath,
      'user_memory_file_path': userMemoryFilePath,
      'sessions_directory_path': OpenHandPaths.defaultSessionsDirectoryPath(),
      'compression_threshold_chars': compressionThresholdChars,
      'memory_enabled': memoryEnabled,
      'memory_entry_count': memoryEntries.length,
    };
  }
}
